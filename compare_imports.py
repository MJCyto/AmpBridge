#!/usr/bin/env python3
"""
Compare Settings Imports

This script compares the two settings import files to find differences
and understand what data actually changes when zones are on/off.
"""

import json

def load_settings_data(filename):
    """Load the settings import JSON data"""
    with open(filename, 'r') as f:
        return json.load(f)

def compare_hex_data(file1, file2):
    """Compare hex data between the two files"""
    print("=== HEX DATA COMPARISON ===\n")
    
    data1 = load_settings_data(file1)
    data2 = load_settings_data(file2)
    
    print(f"File 1 ({file1}): {len(data1)} messages")
    print(f"File 2 ({file2}): {len(data2)} messages")
    
    # Look for differences in hex data
    differences = []
    
    for i, (msg1, msg2) in enumerate(zip(data1, data2)):
        if msg1['hex'] != msg2['hex']:
            differences.append({
                'position': i,
                'file1_hex': msg1['hex'],
                'file2_hex': msg2['hex'],
                'file1_desc': msg1['description'],
                'file2_desc': msg2['description']
            })
    
    if differences:
        print(f"Found {len(differences)} differences:")
        for diff in differences[:10]:  # Show first 10
            print(f"  Position {diff['position']}:")
            print(f"    File 1: {diff['file1_hex']} - {diff['file1_desc']}")
            print(f"    File 2: {diff['file2_hex']} - {diff['file2_desc']}")
            print()
    else:
        print("No differences found in hex data!")
    
    return differences

def compare_timestamps(file1, file2):
    """Compare timestamps between the two files"""
    print("=== TIMESTAMP COMPARISON ===\n")
    
    data1 = load_settings_data(file1)
    data2 = load_settings_data(file2)
    
    # Look at first and last timestamps
    print(f"File 1 ({file1}):")
    print(f"  First: {data1[0]['timestamp']}")
    print(f"  Last:  {data1[-1]['timestamp']}")
    
    print(f"\nFile 2 ({file2}):")
    print(f"  First: {data2[0]['timestamp']}")
    print(f"  Last:  {data2[-1]['timestamp']}")
    
    # Calculate duration
    from datetime import datetime
    start1 = datetime.fromisoformat(data1[0]['timestamp'].replace('Z', '+00:00'))
    end1 = datetime.fromisoformat(data1[-1]['timestamp'].replace('Z', '+00:00'))
    duration1 = (end1 - start1).total_seconds()
    
    start2 = datetime.fromisoformat(data2[0]['timestamp'].replace('Z', '+00:00'))
    end2 = datetime.fromisoformat(data2[-1]['timestamp'].replace('Z', '+00:00'))
    duration2 = (end2 - start2).total_seconds()
    
    print(f"\nDuration:")
    print(f"  File 1: {duration1:.2f} seconds")
    print(f"  File 2: {duration2:.2f} seconds")

def look_for_text_patterns(file1, file2):
    """Look for text patterns that might contain zone names"""
    print("\n=== TEXT PATTERN SEARCH ===\n")
    
    data1 = load_settings_data(file1)
    data2 = load_settings_data(file2)
    
    # Look for ASCII text in both files
    def find_text_sequences(data):
        sequences = []
        current_sequence = []
        
        for msg in data:
            hex_val = msg['hex']
            try:
                if ' ' in hex_val:
                    # Multi-byte hex
                    bytes_list = [int(b, 16) for b in hex_val.split()]
                    ascii_chars = [chr(b) if 32 <= b <= 126 else '.' for b in bytes_list]
                    ascii_str = ''.join(ascii_chars)
                else:
                    # Single byte hex
                    byte_val = int(hex_val, 16)
                    ascii_char = chr(byte_val) if 32 <= byte_val <= 126 else '.'
                    ascii_str = ascii_char
                
                if ascii_str.isprintable() and not ascii_str.isspace():
                    current_sequence.append((msg, ascii_str))
                else:
                    if len(current_sequence) >= 3:  # Minimum 3 printable chars
                        sequences.append(current_sequence)
                    current_sequence = []
            except:
                if len(current_sequence) >= 3:
                    sequences.append(current_sequence)
                current_sequence = []
        
        # Add final sequence if it exists
        if len(current_sequence) >= 3:
            sequences.append(current_sequence)
        
        return sequences
    
    sequences1 = find_text_sequences(data1)
    sequences2 = find_text_sequences(data2)
    
    print(f"File 1 text sequences: {len(sequences1)}")
    for i, seq in enumerate(sequences1):
        text = ''.join([item[1] for item in seq])
        print(f"  {i+1}: '{text}'")
    
    print(f"\nFile 2 text sequences: {len(sequences2)}")
    for i, seq in enumerate(sequences2):
        text = ''.join([item[1] for item in seq])
        print(f"  {i+1}: '{text}'")
    
    # Look for "Bedroom" specifically
    print("\nSearching for 'Bedroom':")
    for i, msg in enumerate(data1):
        if 'Bedroom' in msg.get('description', ''):
            print(f"  File 1, position {i}: {msg['hex']} - {msg['description']}")
    
    for i, msg in enumerate(data2):
        if 'Bedroom' in msg.get('description', ''):
            print(f"  File 2, position {i}: {msg['hex']} - {msg['description']}")

def analyze_volume_patterns(file1, file2):
    """Look for volume-related patterns"""
    print("\n=== VOLUME PATTERN ANALYSIS ===\n")
    
    data1 = load_settings_data(file1)
    data2 = load_settings_data(file2)
    
    # Look for values that could be volume percentages (0-100)
    def find_volume_candidates(data, filename):
        candidates = []
        for i, msg in enumerate(data):
            hex_val = msg['hex']
            try:
                if ' ' in hex_val:
                    # Multi-byte - look at each byte
                    bytes_list = [int(b, 16) for b in hex_val.split()]
                    for j, byte_val in enumerate(bytes_list):
                        if 0 <= byte_val <= 100:
                            candidates.append({
                                'position': i,
                                'byte_position': j,
                                'value': byte_val,
                                'hex': hex_val,
                                'description': msg['description']
                            })
                else:
                    # Single byte
                    byte_val = int(hex_val, 16)
                    if 0 <= byte_val <= 100:
                        candidates.append({
                            'position': i,
                            'byte_position': 0,
                            'value': byte_val,
                            'hex': hex_val,
                            'description': msg['description']
                        })
            except:
                pass
        return candidates
    
    candidates1 = find_volume_candidates(data1, file1)
    candidates2 = find_volume_candidates(data2, file2)
    
    print(f"File 1 volume candidates: {len(candidates1)}")
    for cand in candidates1[:20]:  # Show first 20
        print(f"  Position {cand['position']}: {cand['value']}% ({cand['hex']})")
    
    print(f"\nFile 2 volume candidates: {len(candidates2)}")
    for cand in candidates2[:20]:  # Show first 20
        print(f"  Position {cand['position']}: {cand['value']}% ({cand['hex']})")
    
    # Look for differences in volume candidates
    print("\nVolume differences:")
    # This would need more sophisticated comparison logic
    print("  (Volume comparison logic would go here)")

def main():
    """Main comparison function"""
    print("Settings Import Comparison")
    print("=" * 50)
    
    file1 = 'settingsImport.json'
    file2 = 'settingsImport2.json'
    
    # Compare hex data
    differences = compare_hex_data(file1, file2)
    
    # Compare timestamps
    compare_timestamps(file1, file2)
    
    # Look for text patterns
    look_for_text_patterns(file1, file2)
    
    # Analyze volume patterns
    analyze_volume_patterns(file1, file2)
    
    # Summary
    print("\n=== SUMMARY ===")
    if differences:
        print(f"Found {len(differences)} differences between imports")
        print("This suggests the configuration data does change when zones are on/off")
    else:
        print("No differences found between imports")
        print("This suggests either:")
        print("  1. Volume levels aren't stored in this data packet")
        print("  2. Zone names aren't in this data packet")
        print("  3. The data structure is more complex than we thought")
        print("  4. The changes are in a different part of the protocol")

if __name__ == "__main__":
    main()

CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" INTEGER PRIMARY KEY, "inserted_at" TEXT);
CREATE TABLE IF NOT EXISTS "audio_devices" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "device_type" TEXT NOT NULL, "room" TEXT, "ip_address" TEXT, "port" INTEGER, "is_active" INTEGER DEFAULT true, "settings" TEXT DEFAULT ('{}'), "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "inputs" JSON DEFAULT ('[]'), "outputs" JSON DEFAULT ('[]'));
CREATE TABLE sqlite_sequence(name,seq);
CREATE INDEX "audio_devices_room_index" ON "audio_devices" ("room");
CREATE INDEX "audio_devices_device_type_index" ON "audio_devices" ("device_type");
CREATE INDEX "audio_devices_is_active_index" ON "audio_devices" ("is_active");
INSERT INTO schema_migrations VALUES(20241201000000,'2025-08-17T03:34:25');
INSERT INTO schema_migrations VALUES(20250817025142,'2025-08-17T03:34:25');

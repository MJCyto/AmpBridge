/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./js/**/*.js",
    "./css/**/*.css",
    "../lib/amp_bridge_web.ex",
    "../lib/amp_bridge_web/**/*.ex",
    "../lib/amp_bridge_web/**/*.heex",
    "../lib/amp_bridge_web/**/*.html.heex"
  ],
  // Disable purging in development to allow all Tailwind classes
  safelist: [
    // Always include all classes - remove this in production if needed
    { pattern: /.*/ }
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
  ],
}

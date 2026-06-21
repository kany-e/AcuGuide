/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        surface: '#101113',
        panel: '#171a1f',
        'panel-2': '#20242a',
        lime: '#c8ff3d',
        'lime-2': '#e2ff86',
        muted: '#9ba1a7',
        soft: '#6f767d',
        'c-orange': '#ff8a3d',
        'c-red': '#ff6b5f',
        'c-blue': '#82d8ff',
      },
    },
  },
  plugins: [],
}

/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // ── Atlas ink-and-gold palette (the canonical theme). The legacy token NAMES
        //    are remapped to atlas VALUES so existing classes adopt the new look.
        surface: '#e9e5da',   // page ground (warm parchment)
        panel: '#f4f2ea',     // cards / panels
        'panel-2': '#ece9e0',
        lime: '#9a7d44',      // primary accent -> gold
        'lime-2': '#b6975a',
        muted: '#6f746a',
        soft: '#9a9a8a',
        'c-orange': '#b07a35',
        'c-red': '#b04a2f',   // terracotta -> alerts / stop
        'c-blue': '#5f8a63',  // jade -> good / info

        // explicit atlas names for new components
        paper: '#ece9e0',
        paper2: '#f4f2ea',
        gold: '#9a7d44',
        'gold-soft': '#7c6531',
        jade: '#5f8a63',
        parch: '#2f332c',
        ink: '#33372f',       // primary text
        'ink-dim': '#767b6e',
        line: '#5a5032',      // hairline borders (use with opacity)
      },
    },
  },
  plugins: [],
}

import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'fs'
import os from 'os'
import path from 'path'

const mkcertDir = path.join(os.homedir(), '.vite-plugin-mkcert')

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    https: {
      key: fs.readFileSync(path.join(mkcertDir, 'dev.pem')),
      cert: fs.readFileSync(path.join(mkcertDir, 'cert.pem')),
    },
  },
})

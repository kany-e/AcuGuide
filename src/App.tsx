import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import HomePage from './pages/HomePage'
import SafetyPage from './pages/SafetyPage'
import RoutinePage from './pages/RoutinePage'
import CameraPage from './pages/CameraPage'
import RecapPage from './pages/RecapPage'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/safety/:symptomId" element={<SafetyPage />} />
        <Route path="/routine/:symptomId" element={<RoutinePage />} />
        <Route path="/camera/:symptomId" element={<CameraPage />} />
        <Route path="/recap" element={<RecapPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}

import { createRoot } from 'react-dom/client';
import MeridianAtlas from './MeridianAtlas.jsx';
import './styles.css';

// NOTE: React.StrictMode intentionally removed. Its double-invoke of effects
// breaks getUserMedia (camera) in the AR Coach view (AbortError on iOS Safari).
createRoot(document.getElementById('root')).render(<MeridianAtlas />);

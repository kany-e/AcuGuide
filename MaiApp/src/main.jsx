import React from 'react';
import { createRoot } from 'react-dom/client';
import MeridianAtlas from './MeridianAtlas.jsx';
import './styles.css';

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <MeridianAtlas />
  </React.StrictMode>
);

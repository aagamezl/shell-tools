const statusElement = document.getElementById("status");
const loaded = new Date().toLocaleTimeString();

statusElement.textContent = "script.js loaded at " + loaded;

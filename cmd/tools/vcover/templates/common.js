// V Coverage Report - Common JavaScript
(function() {
    // Initialize dark mode from localStorage or system preference
    try {
        var stored = localStorage.getItem('vcover-dark-mode');
        if (stored === 'true' || (stored === null && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
            document.documentElement.classList.add('dark');
        }
    } catch(e) {
        if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
            document.documentElement.classList.add('dark');
        }
    }
})();

function toggleDark() {
    document.documentElement.classList.toggle('dark');
    try { localStorage.setItem('vcover-dark-mode', document.documentElement.classList.contains('dark')); } catch(e) {}
}

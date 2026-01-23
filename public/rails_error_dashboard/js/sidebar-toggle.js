// Sidebar toggle functionality
document.addEventListener('DOMContentLoaded', function() {
  const sidebarToggle = document.getElementById('sidebarToggle');
  const sidebar = document.getElementById('sidebar');
  const mainContent = document.getElementById('mainContent');
  const STORAGE_KEY = 'rails_error_dashboard_sidebar_collapsed';

  if (!sidebarToggle || !sidebar || !mainContent) return;

  // Check localStorage for saved state
  const isCollapsed = localStorage.getItem(STORAGE_KEY) === 'true';

  // Apply saved state on page load
  if (isCollapsed) {
    sidebar.classList.add('sidebar-collapsed');
    mainContent.classList.add('content-expanded');
  }

  // Toggle sidebar on button click
  sidebarToggle.addEventListener('click', function() {
    const willBeCollapsed = !sidebar.classList.contains('sidebar-collapsed');

    // Toggle classes
    sidebar.classList.toggle('sidebar-collapsed');
    mainContent.classList.toggle('content-expanded');

    // Save state to localStorage
    localStorage.setItem(STORAGE_KEY, willBeCollapsed);

    // Optional: Add animation feedback
    const icon = sidebarToggle.querySelector('i');
    if (icon) {
      icon.style.transform = 'rotate(180deg)';
      setTimeout(() => {
        icon.style.transform = '';
      }, 200);
    }
  });

  // Keyboard shortcut: Press 'S' to toggle sidebar
  document.addEventListener('keydown', function(e) {
    // Only trigger if not in an input field
    if (e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA' && !e.target.isContentEditable) {
      if (e.key === 's' || e.key === 'S') {
        e.preventDefault();
        sidebarToggle.click();
      }
    }
  });
});

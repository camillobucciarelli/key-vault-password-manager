// content.js - Injects the KeyVault UI into password fields

console.log("[KeyVault] Content script loaded");

const KEYVAULT_LOGO_SVG = `
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M18 8H17V6C17 3.24 14.76 1 12 1C9.24 1 7 3.24 7 6V8H6C4.9 8 4 8.9 4 10V20C4 21.1 4.9 22 6 22H18C19.1 22 20 21.1 20 20V10C20 8.9 19.1 8 18 8ZM9 6C9 4.34 10.34 3 12 3C13.66 3 15 4.34 15 6V8H9V6ZM12 17C10.9 17 10 16.1 10 15C10 13.9 10.9 13 12 13C13.1 13 14 13.9 14 15C14 16.1 13.1 17 12 17Z" fill="currentColor"/>
</svg>
`;

function attachKeyVaultUI() {
    // 1. Find all password fields that haven't been processed yet
    const passwordInputs = document.querySelectorAll('input[type="password"]:not([data-keyvault-attached="true"])');
    
    passwordInputs.forEach(input => {
        // Mark as attached to prevent duplication
        input.setAttribute('data-keyvault-attached', 'true');

        // Create the button
        const vaultButton = document.createElement('button');
        vaultButton.className = 'keyvault-autofill-btn';
        vaultButton.innerHTML = KEYVAULT_LOGO_SVG;
        vaultButton.title = 'KeyVault AutoFill';
        vaultButton.type = 'button'; // Prevent form submission

        // The input needs a relative wrapper to position the button absolutely inside it
        // We create a wrapper and place the input and button inside
        const wrapper = document.createElement('div');
        wrapper.className = 'keyvault-autofill-wrapper';
        
        // Wrap the input element carefully
        input.parentNode.insertBefore(wrapper, input);
        wrapper.appendChild(input);
        wrapper.appendChild(vaultButton);

        // Click handler
        vaultButton.addEventListener('click', async (e) => {
            e.preventDefault();
            e.stopPropagation();
            
            vaultButton.style.opacity = '0.5';
            
            const currentUrl = window.location.href;
            console.log(`[KeyVault] Requesting credentials for: ${currentUrl}`);
            
            try {
                // Send message to Background Worker
                const response = await chrome.runtime.sendMessage({ 
                    action: "get_credentials", 
                    url: currentUrl 
                });
                
                vaultButton.style.opacity = '1';

                if (response && response.success && response.credentials && response.credentials.length > 0) {
                    // For now, auto-fill with the first match
                    const cred = response.credentials[0];
                    console.log(`[KeyVault] Found credentials for: ${cred.username}`);
                    
                    // Auto-fill Logic
                    const form = input.closest('form') || document.body;
                    
                    // Find username field (often text, email, or tel before password)
                    const userField = form.querySelector('input[type="text"], input[type="email"], input[type="tel"]');
                    if (userField && cred.username) {
                        userField.value = cred.username;
                        triggerInputEvents(userField);
                    }
                    
                    // Fill password
                    if (cred.password) {
                        input.value = cred.password;
                        triggerInputEvents(input);
                    }

                    // Optional visual feedback
                    vaultButton.style.color = '#818cf8';
                    setTimeout(() => vaultButton.style.color = '', 2000);
                } else {
                    console.log("[KeyVault] No credentials found or error:", response?.error);
                    alert("KeyVault: No credentials found for this site or Vault locked.");
                }
            } catch (err) {
                console.error("[KeyVault] Extension communication error:", err);
                vaultButton.style.opacity = '1';
                alert("KeyVault Extension requires Native App to be running.");
            }
        });
    });
}

// Helper to simulate React/Angular change events
function triggerInputEvents(element) {
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    // React specific hack: update the internal tracker 
    let tracker = element._valueTracker;
    if (tracker) tracker.setValue(element.value);
}

// Ensure it runs on load
attachKeyVaultUI();

// Watch for DOM changes (Single Page Apps)
const observer = new MutationObserver((mutations) => {
    // Only fire if elements were added to avoid infinite loops
    let hasAddedNodes = mutations.some(mutation => mutation.addedNodes.length > 0);
    if (hasAddedNodes) {
        // Use a small delay/debounce to not freeze the page on heavy renders
        setTimeout(attachKeyVaultUI, 500);
    }
});

observer.observe(document.body, { 
    childList: true, 
    subtree: true,
    attributes: false
});

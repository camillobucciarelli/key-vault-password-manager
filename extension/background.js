// background.js - Service Worker
// Manages the connection between the web page and the Native application.

const NATIVE_HOST_NAME = "com.cbucciarelli.keyvault";
let nativePort = null;
let pendingRequests = new Map();
let requestCounter = 0;

console.log("[KeyVault] Background service worker initialized.");

function connectToNativeHost() {
    console.log(`[KeyVault] Attempting connection to native host: ${NATIVE_HOST_NAME}`);
    try {
        nativePort = chrome.runtime.connectNative(NATIVE_HOST_NAME);
        
        nativePort.onMessage.addListener((message) => {
            console.log("[KeyVault] Received from Native:", message);
            
            // Re-route the answer back to the content script that asked for it
            if (message.requestId && pendingRequests.has(message.requestId)) {
                const resolve = pendingRequests.get(message.requestId);
                pendingRequests.delete(message.requestId);
                
                if (message.ok) {
                    resolve({ success: true, credentials: message.credentials });
                } else {
                    resolve({ success: false, error: message.error });
                }
            }
        });

        nativePort.onDisconnect.addListener(() => {
            console.log("[KeyVault] Native connection disconnected.", chrome.runtime.lastError?.message);
            nativePort = null;
            
            // Reject all pending requests
            for (const [id, resolve] of pendingRequests.entries()) {
                resolve({ success: false, error: "Native Host disconnected" });
            }
            pendingRequests.clear();
        });
    } catch (e) {
        console.error("[KeyVault] Failed to connect to Native Host:", e);
    }
}

// Initial connection
connectToNativeHost();

// Listen for messages from content.js
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "get_credentials") {
        console.log(`[KeyVault] Received request from tab for URL: ${request.url}`);
        
        if (!nativePort) {
            console.log("[KeyVault] Native port lost, trying to reconnect...");
            connectToNativeHost();
        }
        
        if (!nativePort) {
            sendResponse({ success: false, error: "Cannot connect to KeyVault Mac App." });
            return false;
        }

        const requestId = `req_${++requestCounter}`;
        
        // Store the callback
        pendingRequests.set(requestId, sendResponse);
        
        // Send request array/JSON to the native Dart script
        try {
            nativePort.postMessage({
                requestId: requestId,
                type: "findCredentials",
                url: request.url,
                limit: 5
            });
            console.log(`[KeyVault] Sent request ${requestId} to Native.`);
        } catch (e) {
            console.error("[KeyVault] POST to native failed", e);
            pendingRequests.delete(requestId);
            sendResponse({ success: false, error: "Failed to send message to native host" });
        }
        
        // Return true indicates we will respond asynchronously
        return true; 
    }
});

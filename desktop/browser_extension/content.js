function findUsernameField(passwordField) {
  if (!passwordField) {
    return null;
  }

  const form = passwordField.form;
  if (form) {
    const candidates = form.querySelectorAll(
      'input[type="email"], input[type="text"], input[autocomplete="username"], input[name*="user" i], input[name*="email" i], input[id*="user" i], input[id*="email" i]'
    );
    if (candidates.length > 0) {
      return candidates[0];
    }
  }

  let previous = passwordField.previousElementSibling;
  while (previous) {
    if (
      previous.tagName === "INPUT" &&
      (previous.type === "text" || previous.type === "email")
    ) {
      return previous;
    }
    previous = previous.previousElementSibling;
  }

  return null;
}

function findPasswordField() {
  const focused = document.activeElement;
  if (focused && focused.tagName === "INPUT" && focused.type === "password") {
    return focused;
  }

  const passwordInputs = document.querySelectorAll('input[type="password"]');
  if (passwordInputs.length === 0) {
    return null;
  }
  return passwordInputs[0];
}

function setNativeInputValue(input, value) {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype,
    "value"
  )?.set;
  if (setter) {
    setter.call(input, value);
  } else {
    input.value = value;
  }
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

function fillCredential(credential) {
  const passwordField = findPasswordField();
  if (!passwordField) {
    return { ok: false, error: "Password field not found on this page." };
  }

  const usernameField = findUsernameField(passwordField);
  if (usernameField && credential.username) {
    setNativeInputValue(usernameField, credential.username);
  }
  if (credential.password) {
    setNativeInputValue(passwordField, credential.password);
  }

  return { ok: true };
}

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request?.type !== "KEYVAULT_FILL_ACTIVE_CREDENTIAL") {
    return false;
  }

  const response = fillCredential(request.payload || {});
  sendResponse(response);
  return false;
});

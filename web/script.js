const form = document.querySelector("#join");
const emailInput = document.querySelector("#email");
const formNote = document.querySelector("#form-note");
const submitButton = form.querySelector("button[type='submit']");
const submitLabel = submitButton.querySelector("span");
const defaultNote = formNote.textContent.trim();

document.querySelector("#year").textContent = new Date().getFullYear();

function setFormState(message, state = "") {
  formNote.textContent = message;
  formNote.classList.toggle("is-error", state === "error");
  formNote.classList.toggle("is-success", state === "success");
}

function rememberSignup(email) {
  const existing = JSON.parse(localStorage.getItem("flowdock-waitlist") || "[]");
  if (!existing.includes(email)) {
    existing.push(email);
    localStorage.setItem("flowdock-waitlist", JSON.stringify(existing));
  }
}

async function submitEmail(email) {
  const endpoint = form.dataset.endpoint.trim();

  if (!endpoint) {
    rememberSignup(email);
    return;
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, source: "flowdock-launch-site" }),
  });

  if (!response.ok) {
    throw new Error("Signup request failed");
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  setFormState(defaultNote);

  const email = emailInput.value.trim().toLowerCase();
  if (!email || !emailInput.validity.valid) {
    setFormState("Enter a valid email address so we know where to send your invite.", "error");
    emailInput.focus();
    return;
  }

  submitButton.disabled = true;
  submitLabel.textContent = "Joining…";

  try {
    await submitEmail(email);
    form.reset();
    setFormState("You’re on the list. We’ll be in touch when Flowdock is ready.", "success");
    submitLabel.textContent = "You’re on the list";
  } catch {
    setFormState("We couldn’t add you just now. Please try again in a moment.", "error");
    submitLabel.textContent = "Join the launch list";
  } finally {
    submitButton.disabled = false;
  }
});

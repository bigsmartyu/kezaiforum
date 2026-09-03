(() => {
  const initialMode = document.body.dataset.initialMode === "register" ? "register" : "login";
  const modeButtons = [...document.querySelectorAll("[data-mode-button]")];
  const modePanels = [...document.querySelectorAll("[data-mode-panel]")];
  const forms = [...document.querySelectorAll("[data-submit-form]")];
  const avatar = document.getElementById("avatar");
  const preview = document.getElementById("avatar-preview");
  const avatarName = document.getElementById("avatar-name");
  const loginUsername = document.getElementById("login-username");
  const loginAvatar = document.getElementById("login-avatar-preview");
  const loginAvatarName = document.getElementById("login-avatar-name");
  const rememberedUsername = document.body.dataset.rememberedUsername || "";
  const defaultAvatar = document.body.dataset.defaultAvatar || "";
  let previewUrl;

  const activateMode = (mode) => {
    modeButtons.forEach((button) => {
      const active = button.dataset.modeButton === mode;
      button.classList.toggle("active", active);
      button.setAttribute("aria-selected", active ? "true" : "false");
    });
    modePanels.forEach((panel) => {
      panel.hidden = panel.dataset.modePanel !== mode;
    });
  };

  modeButtons.forEach((button) => {
    button.addEventListener("click", () => activateMode(button.dataset.modeButton));
  });
  activateMode(initialMode);

  if (avatar && preview && avatarName) {
    avatar.addEventListener("change", () => {
      const file = avatar.files && avatar.files[0];
      if (!file) {
        avatarName.textContent = "未选择时使用系统头像";
        return;
      }

      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = URL.createObjectURL(file);
      preview.src = previewUrl;
      avatarName.textContent = file.name;
    });
  }

  if (loginUsername && loginAvatar && loginAvatarName) {
    const refreshRememberedProfile = () => {
      const matches = rememberedUsername && loginUsername.value.trim().toLowerCase() === rememberedUsername.toLowerCase();
      loginAvatar.src = matches ? loginAvatar.dataset.rememberedAvatar : defaultAvatar;
      loginAvatarName.textContent = matches ? `上次使用：${rememberedUsername}` : "尚未保存此账号";
    };
    loginUsername.addEventListener("input", refreshRememberedProfile);
    refreshRememberedProfile();
  }

  forms.forEach((form) => {
    form.addEventListener("submit", () => {
      const submit = form.querySelector("button[type=submit]");
      if (!submit) return;
      submit.disabled = true;
      submit.textContent = form.id === "join-form" ? "正在登记…" : "正在登录…";
    });
  });

  window.addEventListener("pagehide", () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  });
})();

// The Download buttons: when a donation link is set, they first open a small "it's free,
// a coffee is welcome" screen; either choice starts the download.
(() => {
  const donate = document.querySelector('meta[name="brimtune-donate"]')?.content.trim();
  const dialog = document.getElementById("getit");
  if (!donate || !dialog?.showModal) return;

  const done = dialog.querySelector(".getit-done");
  const lenis = () => window.brimtuneLenis;
  dialog.querySelector("[data-getit-donate]").href = donate;

  function download() {
    // A hidden link keeps the page where it is; the file comes as an attachment.
    const link = document.createElement("a");
    link.href = "/Brimtune.dmg";
    link.download = "Brimtune.dmg";
    document.body.append(link);
    link.click();
    link.remove();
    done.hidden = false;
  }

  function close() {
    dialog.close();
  }

  document.querySelectorAll('a[href="/Brimtune.dmg"]:not([data-getit-free])').forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      done.hidden = true;
      lenis()?.stop();
      dialog.showModal();
    });
  });
  dialog.addEventListener("close", () => { if (lenis()?.isStopped) lenis().start(); });

  // The coffee link opens in a new tab by itself; the download starts here.
  dialog.querySelector("[data-getit-donate]").addEventListener("click", download);
  dialog.querySelector("[data-getit-free]").addEventListener("click", (e) => {
    e.preventDefault();
    download();
  });
  dialog.querySelectorAll("[data-getit-close]").forEach((el) => el.addEventListener("click", close));
  // A click on the dimmed backdrop (the dialog itself, outside its panels) closes it.
  dialog.addEventListener("click", (e) => { if (e.target === dialog) close(); });
})();

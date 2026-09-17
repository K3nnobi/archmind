# ArchMind 1.5.18 Release Notes

The optional Firefox / ChatGPT Color Emoji Fix targets the default Firefox
profile detected from profiles.ini. It installs noto-fonts-emoji if needed,
refreshes fontconfig, enables Firefox custom styles through user.js, and
inserts a managed rule into chrome/userContent.css.

The font order is OpenAI Sans, Noto Color Emoji, Adwaita Sans, then sans-serif.
Existing Firefox customizations stay in place. The first modification of an
existing file creates a safety copy in
~/ArchMind/Backups/Safety/firefox-chatgpt-emoji; repeated applications do
not duplicate the CSS or preference. Rollback restores the prior managed CSS
block and prior stylesheet preference only when ArchMind changed them.

Open the patch from Package Center or its removal from Rollback Center.
Fully restart Firefox after applying or removing it. The main installation
does not apply the patch automatically. The module does not terminate Firefox.

//
//  Injection.swift
//  ChatGPT-Mac
//
//  User scripts injected into chatgpt.com: CSS that hides duplicated web chrome,
//  makes the web sidebar transparent so native glass shows through it, and a
//  JavaScript bridge that reports page state back to Swift.
//

import WebKit

enum Injection {
    static let homeURL = URL(string: "https://chatgpt.com/")!
    /// Deep link that opens the settings dialog in the web app.
    static let settingsURL = URL(string: "https://chatgpt.com/#settings/General")!
    static let messageHandlerName = "bridge"
    static let settingsNavigationHandlerName = "settingsNavigation"

    /// Safari user agent so Google / Apple sign-in flows don't reject the embedded web view.
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    // MARK: - DOM selectors (kept together so they're easy to patch when OpenAI changes their markup)

    /// Containers of ChatGPT's own sidebar. Kept visible, but their backgrounds are
    /// cleared so the native glass panel behind the web view shows through.
    static let webSidebarSelectors = [
        "#stage-slideover-sidebar",
        "[data-testid=\"left-sidebar\"]",
        "nav[aria-label=\"Chat history\"]",
    ]

    /// Header/chrome elements that duplicate native UI. The whole page header is hidden
    /// (its share button and model switcher are driven from the native toolbar via JS
    /// clicks), and the sidebar collapse toggles are hidden so the sidebar stays open
    /// behind the fixed-width glass panel.
    static let webChromeSelectors = [
        "#page-header",
        "[data-testid=\"open-sidebar-button\"]",
        "[data-testid=\"close-sidebar-button\"]",
        "button[aria-label*=\"sidebar\" i]",
    ]

    /// Header controls mirrored into the native toolbar.
    static let shareButtonSelector = "[data-testid=\"share-chat-button\"]"
    static let modelSwitcherSelector = "[data-testid=\"model-switcher-dropdown-button\"]"
    static let conversationMenuSelector = "[data-testid=\"conversation-options-button\"]"
    static let temporaryChatSelector = "[data-testid=\"temporary-chat-button\"], button[aria-label*=\"temporary\" i]"

    /// Elements that indicate a signed-in app shell. Alternate routes such as
    /// GPTs, Library, Projects, and Plugins do not always mount the composer,
    /// so include persistent signed-in navigation/account affordances too.
    static let loggedInProbe = "#prompt-textarea, form [contenteditable=\"true\"], main form textarea, [data-testid=\"left-sidebar\"], nav[aria-label=\"Chat history\"], a[href=\"/library\"], a[href=\"/gpts\"], button[aria-label*=\"profile\" i], button[aria-label*=\"account\" i], [data-testid*=\"profile\" i], [data-testid*=\"account\" i]"
    /// Elements that indicate the logged-out marketing/login page.
    static let loggedOutProbe = "[data-testid=\"login-button\"], [data-testid=\"signup-button\"]"

    // MARK: - Scripts

    static var userScripts: [WKUserScript] {
        [
            WKUserScript(source: styleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
        ]
    }

    /// Scripts for compact floating chat windows: everything the main window gets,
    /// plus CSS that hides the sidebar entirely and makes the chat surface
    /// transparent so the window's glass material shows through the conversation.
    static var floatingWindowUserScripts: [WKUserScript] {
        let hide = webSidebarSelectors.joined(separator: ", ")
        // `body main` outranks the shared stylesheet's plain `main` selector, so the
        // transparent rule wins regardless of which <style> tag ends up last.
        let css = """
        \(hide) { display: none !important; } \
        body main, body #thread, body main > div { background-color: transparent !important; background-image: none !important; }
        """
        let source = """
        (function () {
            function install() {
                if (document.getElementById('cgpt-floating-style')) { return; }
                var style = document.createElement('style');
                style.id = 'cgpt-floating-style';
                style.textContent = '\(css)';
                (document.head || document.documentElement).appendChild(style);
            }
            install();
            new MutationObserver(install).observe(document.documentElement, { childList: true, subtree: false });
        })();
        """
        return userScripts + [WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)]
    }

    /// Width of the settings dialog's nav column, aligned with the main native glass panel.
    static let settingsSidebarWidth: CGFloat = SidebarView.width

    /// Scripts for the native Settings window: hides duplicated app chrome so only the
    /// settings dialog is visible, stretched to fill the window. Mirrors the main
    /// window's treatment: the dialog's nav column is transparent (native glass
    /// shows through), while the content pane keeps an opaque surface.
    static var settingsWindowUserScripts: [WKUserScript] {
        let hideShell = (webSidebarSelectors + ["#page-header"]).joined(separator: ", ")
        let navWidth = Int(settingsSidebarWidth)
        let css = """
        \(hideShell) { display: none !important; } \
        div.cgpt-settings-root { position: fixed !important; inset: 0 !important; \
        transform: none !important; translate: none !important; margin: 0 !important; \
        width: 100vw !important; height: 100vh !important; \
        max-width: none !important; max-height: none !important; \
        border-radius: 0 !important; box-shadow: none !important; border: none !important; \
        background-color: transparent !important; } \
        .cgpt-settings-root-close { display: none !important; } \
        .cgpt-settings-nav { \
        background-color: transparent !important; background-image: none !important; \
        padding-top: 20px !important; \
        width: \(navWidth)px !important; min-width: \(navWidth)px !important; max-width: \(navWidth)px !important; } \
        main { visibility: hidden !important; } \
        .cgpt-settings-panel { \
        background-color: var(--main-surface-primary, Canvas) !important; } \
        [data-radix-popper-content-wrapper], [role="listbox"], [role="menu"] { \
        visibility: visible !important; z-index: 2147483647 !important; pointer-events: auto !important; }
        """
        let styleSource = """
        (function () {
            var classificationScheduled = false;

            function install() {
                if (document.getElementById('cgpt-settings-style')) { return; }
                var style = document.createElement('style');
                style.id = 'cgpt-settings-style';
                style.textContent = '\(css)';
                (document.head || document.documentElement).appendChild(style);
            }

            function clearSettingsNavBackgrounds(nav) {
                var navRect = nav.getBoundingClientRect();
                if (navRect.width < 40 || navRect.height < 40) { return; }
                var nodes = Array.from(nav.querySelectorAll('*'));
                nodes.forEach(function (el) {
                    var rect = el.getBoundingClientRect();
                    var coversNav = rect.width >= navRect.width * 0.85
                        && rect.height >= navRect.height * 0.5;
                    if (!coversNav) { return; }
                    el.style.setProperty('background-color', 'transparent', 'important');
                    el.style.setProperty('background-image', 'none', 'important');
                    el.style.setProperty('box-shadow', 'none', 'important');
                    el.style.setProperty('-webkit-backdrop-filter', 'none', 'important');
                    el.style.setProperty('backdrop-filter', 'none', 'important');
                });
            }

            // Only the outer settings dialog should fill this native window.
            // Dialogs opened from it must keep the site's normal modal sheet
            // layout, including their rounded card, backdrop, and close button.
            function classifyDialogs() {
                classificationScheduled = false;
                var dialogs = Array.from(document.querySelectorAll('div[role="dialog"]'));
                var labels = ['general', 'notifications', 'personalization', 'data controls'];
                var root = null;
                var bestScore = 0;

                dialogs.forEach(function (dialog) {
                    var text = (dialog.textContent || '').toLowerCase();
                    var score = dialog.querySelector('[role="tablist"]') ? 4 : 0;
                    labels.forEach(function (label) {
                        if (text.indexOf(label) !== -1) { score++; }
                    });
                    if (score > bestScore) {
                        root = dialog;
                        bestScore = score;
                    }
                });

                document.querySelectorAll(
                    '.cgpt-settings-root, .cgpt-settings-root-close, ' +
                    '.cgpt-settings-nav, .cgpt-settings-panel'
                ).forEach(function (element) {
                    element.classList.remove(
                        'cgpt-settings-root',
                        'cgpt-settings-root-close',
                        'cgpt-settings-nav',
                        'cgpt-settings-panel'
                    );
                });
                if (!root || bestScore < 3) { return; }

                root.classList.add('cgpt-settings-root');
                root.querySelectorAll('button[aria-label="Close" i]').forEach(function (button) {
                    if (button.closest('div[role="dialog"]') === root) {
                        button.classList.add('cgpt-settings-root-close');
                    }
                });
                root.querySelectorAll('[role="tablist"], nav').forEach(function (nav) {
                    if (nav.closest('div[role="dialog"]') === root) {
                        nav.classList.add('cgpt-settings-nav');
                        clearSettingsNavBackgrounds(nav);
                    }
                });
                root.querySelectorAll('[role="tabpanel"]').forEach(function (panel) {
                    if (panel.closest('div[role="dialog"]') === root) {
                        panel.classList.add('cgpt-settings-panel');
                    }
                });
            }

            function scheduleClassification() {
                if (classificationScheduled) { return; }
                classificationScheduled = true;
                requestAnimationFrame(classifyDialogs);
            }

            install();
            scheduleClassification();
            new MutationObserver(function () {
                install();
                scheduleClassification();
            }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        // If the dialog gets dismissed (Escape, backdrop click), bring it back.
        // Before the dialog has been seen once, only nudge the hash (the SPA can
        // take a while to hydrate); reloading during boot caused reload loops.
        let keepOpenSource = """
        (function () {
            var seen = false;
            var missing = 0;
            setInterval(function () {
                if (!document.querySelector('main')) { return; }
                if (document.querySelector('div[role="dialog"]')) { seen = true; missing = 0; return; }
                missing++;
                if (!seen) {
                    // Still booting: re-assert the deep link, never reload.
                    if (missing % 3 === 0) {
                        var h = location.hash || '';
                        var target = h.indexOf('settings') !== -1 ? h : '#settings/General';
                        location.hash = '';
                        location.hash = target;
                    }
                    return;
                }
                if (missing >= 2) {
                    missing = 0;
                    if ((location.hash || '').indexOf('settings') !== -1) {
                        location.reload();
                    } else {
                        location.hash = '#settings/General';
                    }
                }
            }, 1200);
        })();
        """

        // Deep-link fallback: the hash doesn't always select the right tab, so
        // Swift retries this until the dialog is up and the tab is clicked.
        // Scans every dialog (placeholders included) for tab-like elements.
        let tabSource = """
        (function () {
            function candidates() {
                var result = [];
                document.querySelectorAll('div[role="dialog"]').forEach(function (dialog) {
                    dialog.querySelectorAll('[role="tab"], [role="tablist"] button, nav button, nav a')
                        .forEach(function (t) { result.push(t); });
                });
                return result;
            }

            window.__cgptSelectSettingsTab = function (name) {
                var tabs = candidates();
                if (!tabs.length) { return false; }
                var wanted = (name || '').toLowerCase();
                function label(t) { return (t.textContent || '').trim().toLowerCase(); }
                var target = tabs.find(function (t) { return label(t) === wanted; })
                    || tabs.find(function (t) { return label(t).indexOf(wanted) !== -1; });
                if (!target) { return false; }
                if (target.getAttribute('aria-selected') !== 'true'
                    && target.getAttribute('data-state') !== 'active') {
                    target.click();
                }
                return true;
            };
        })();
        """
        // Library links inside settings (such as Storage → Files / Images) belong
        // in the app's persistent main web view, not in the settings-only view.
        // Catch both ordinary anchors and client-side router transitions.
        let navigationSource = """
        (function () {
            if (window.__cgptSettingsNavigationInstalled) { return; }
            window.__cgptSettingsNavigationInstalled = true;

            function isSettingsURL(url) {
                if (url.origin !== location.origin) { return false; }
                var value = url.href.toLowerCase();
                return (url.hash || '').toLowerCase().indexOf('#settings') === 0
                    || value.indexOf('settings') !== -1
                    || value.indexOf('billing') !== -1
                    || value.indexOf('invoice') !== -1
                    || value.indexOf('subscription') !== -1;
            }

            function isBuilderProfileProviderURL(url) {
                if (url.origin !== location.origin) { return false; }
                var value = url.href.toLowerCase();
                return value.indexOf('linkedin') !== -1 || value.indexOf('github') !== -1;
            }

            function postNavigation(type, url) {
                try {
                    window.webkit.messageHandlers.\(settingsNavigationHandlerName)
                        .postMessage({ type: type, url: url.href });
                    return true;
                } catch (e) {
                    return false;
                }
            }

            function openExternal(value) {
                var url;
                try { url = new URL(value, location.href); } catch (e) { return false; }
                if (!isBuilderProfileProviderURL(url)) { return false; }
                return postNavigation('openExternal', url);
            }

            function openInMainWindow(value) {
                var url;
                try { url = new URL(value, location.href); } catch (e) { return false; }
                if (url.origin !== location.origin || isSettingsURL(url)) { return false; }
                return postNavigation('openMainWindow', url);
            }

            function clickSettingsTab(name) {
                var wanted = (name || '').toLowerCase();
                var candidates = [];
                document.querySelectorAll('div[role="dialog"]').forEach(function (dialog) {
                    dialog.querySelectorAll('[role="tab"], [role="tablist"] button, nav button, nav a')
                        .forEach(function (tab) { candidates.push(tab); });
                });
                var target = candidates.find(function (tab) {
                    return (tab.textContent || '').trim().toLowerCase() === wanted;
                }) || candidates.find(function (tab) {
                    return (tab.textContent || '').trim().toLowerCase().indexOf(wanted) !== -1;
                });
                if (!target) { return false; }
                target.click();
                return true;
            }

            // Billing's invoice list is an in-tab detail view. Clicking the
            // already-selected Billing tab does not remount it, so reset via
            // another tab before returning to Billing.
            function resetBillingTab() {
                var resetTab = ['General', 'Notifications', 'Personalization'].find(function (name) {
                    return clickSettingsTab(name);
                });
                if (!resetTab) { return false; }
                setTimeout(function () {
                    if (!clickSettingsTab('Billing')) {
                        location.hash = '#settings/Billing';
                    }
                }, 50);
                return true;
            }

            function isInvoicesViewVisible() {
                return Array.from(document.querySelectorAll(
                    '.cgpt-settings-panel, [role="tabpanel"]'
                )).some(function (panel) {
                    var panelRect = panel.getBoundingClientRect();
                    return Array.from(panel.querySelectorAll(
                        'h1, h2, h3, [role="heading"]'
                    )).some(function (heading) {
                        var headingRect = heading.getBoundingClientRect();
                        return heading.getClientRects().length > 0
                            && (heading.textContent || '').trim().toLowerCase() === 'invoices'
                            && headingRect.top < panelRect.top + 120;
                    });
                });
            }

            function isInvoicesBackControl(event) {
                if (!event.target || !event.target.closest) { return false; }
                var control = event.target.closest('button, a[href], [role="button"]');
                var panel = event.target.closest('.cgpt-settings-panel, [role="tabpanel"]');
                if (!control || !panel) { return false; }
                if ((panel.textContent || '').toLowerCase().indexOf('invoices') === -1) { return false; }

                var label = (
                    control.getAttribute('aria-label')
                    || control.getAttribute('title')
                    || control.textContent
                    || ''
                ).trim().toLowerCase();
                var hasBackLabel = label === 'back' || label.indexOf('back') !== -1 || label.length === 0;
                if (!hasBackLabel || !control.querySelector('svg')) { return false; }

                var controlRect = control.getBoundingClientRect();
                var panelRect = panel.getBoundingClientRect();
                return controlRect.top < panelRect.top + 96
                    && controlRect.left < panelRect.left + 96;
            }

            document.addEventListener('click', function (event) {
                if (!event.target || !event.target.closest) { return; }
                if (isInvoicesBackControl(event)) {
                    setTimeout(function () {
                        if (isInvoicesViewVisible() && !resetBillingTab()) {
                            location.hash = '#settings/Billing';
                        }
                    }, 250);
                }

                var link = event.target.closest('a[href]');
                if (!link || !(openExternal(link.href) || openInMainWindow(link.href))) { return; }
                event.preventDefault();
                event.stopImmediatePropagation();
            }, true);

            ['pushState', 'replaceState'].forEach(function (name) {
                var original = history[name];
                history[name] = function () {
                    if (arguments.length > 2 && arguments[2] != null
                        && (openExternal(arguments[2]) || openInMainWindow(arguments[2]))) {
                        return;
                    }
                    return original.apply(this, arguments);
                };
            });

            var originalOpen = window.open;
            window.open = function (value) {
                if (value != null && openExternal(value)) { return null; }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
        return userScripts + [
            WKUserScript(source: styleSource, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(source: keepOpenSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
            WKUserScript(source: tabSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
            WKUserScript(source: navigationSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
        ]
    }

    private static var css: String {
        let hide = webChromeSelectors.joined(separator: ",\n")
        let sidebar = webSidebarSelectors.joined(separator: ",\n")
        let sidebarChildren = webSidebarSelectors.map { "\($0) nav" }.joined(separator: ",\n")
        return """
        \(hide) {
            display: none !important;
        }
        /* Native backing shows through: page shell, sidebar, and chat column
           are transparent so SwiftUI owns the window background. */
        html, body, body > div, #__next, #root {
            background-color: transparent !important;
            background-image: none !important;
        }
        :root {
            --sidebar-surface-primary: transparent !important;
            --cgpt-native-main-surface: rgb(247 247 248);
        }
        /* Keep the site's dark surface token pitch black for dialogs and
           overlays that still need an opaque web-painted background. */
        html.dark,
        html[data-theme="dark"] {
            --main-surface-primary: #000 !important;
            --cgpt-native-main-surface: #000;
        }
        html.dark main,
        html.dark #thread,
        html.dark main > div,
        html[data-theme="dark"] main,
        html[data-theme="dark"] #thread,
        html[data-theme="dark"] main > div {
            background-color: transparent !important;
            background-image: none !important;
        }
        \(sidebar),
        \(sidebarChildren) {
            background-color: transparent !important;
            background-image: none !important;
        }
        main,
        #thread,
        main > div {
            background-color: transparent !important;
            background-image: none !important;
        }
        /* Route shells such as the GPT store add their own full-page surface
           wrappers. Clear only page-sized structural layers so native SwiftUI
           remains the sole window background, without flattening controls,
           cards, menus, or dialogs that need their own fill. */
        main [class*="bg-token-main-surface-primary"]:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]),
        main [class*="bg-token-bg-primary"]:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]),
        main [class*="bg-token-sidebar-surface-primary"]:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]),
        main .bg-white:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]),
        main .dark\\:bg-gray-950:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]),
        main .min-h-screen,
        main .h-screen,
        main .h-full,
        main .min-h-full,
        main header:not([role="dialog"]),
        main [role="banner"]:not([role="dialog"]) {
            background-color: transparent !important;
            background-image: none !important;
        }
        /* Sticky in-page headers (for example, GPT store search and tabs) need
           an opaque mask so scrolled cards do not show through the controls. */
        main .sticky:not(button):not(input):not(textarea):not([role="button"]):not([role="dialog"]) {
            background-color: var(--cgpt-native-main-surface) !important;
            background-image: none !important;
        }
        /* Native sidebar collapse: __cgptToggleSidebar toggles this class on <html>. */
        \(webSidebarSelectors.map { "html.cgpt-hide-sidebar \($0)" }.joined(separator: ",\n")) {
            display: none !important;
        }
        /* Full-screen web dialogs (e.g. "Upgrade your plan"), tagged by the
           bridge script: fill the window edge-to-edge on the site's surface. */
        div.cgpt-fullscreen-dialog {
            position: fixed !important;
            inset: 0 !important;
            margin: 0 !important;
            transform: none !important;
            translate: none !important;
            width: 100vw !important;
            height: 100vh !important;
            max-width: none !important;
            max-height: none !important;
            border-radius: 0 !important;
            box-shadow: none !important;
            background-color: var(--main-surface-primary, Canvas) !important;
        }
        /* Frosted backing for the sidebar's sticky header (logo, New chat,
           Search chats). The bridge script maintains a single .cgpt-frost-overlay
           spanning from the sidebar top down to the last sticky row, layered
           above the scrolling entries (z 4) but below the header rows (z 5),
           and toggles .cgpt-scrolled while the list is scrolled. */
        .cgpt-frost-overlay {
            position: fixed;
            pointer-events: none;
            z-index: 4;
            opacity: 0;
            transition: opacity 0.15s ease;
            background-color: color-mix(in srgb, Canvas 35%, transparent);
            -webkit-backdrop-filter: blur(24px);
            backdrop-filter: blur(24px);
        }
        \(webSidebarSelectors.map { "\($0).cgpt-scrolled .cgpt-frost-overlay" }.joined(separator: ",\n")) {
            opacity: 1;
        }
        \(webSidebarSelectors.map { "\($0) .cgpt-sticky" }.joined(separator: ",\n")) {
            z-index: 5 !important;
        }
        """
    }

    /// Installs the chrome-hiding CSS as early as possible and keeps it attached
    /// even if the SPA replaces <head> contents.
    private static var styleScript: String {
        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return #"""
        (function () {
            const css = `\#(escapedCSS)`;
            function install() {
                if (document.getElementById('cgpt-native-style')) { return; }
                const style = document.createElement('style');
                style.id = 'cgpt-native-style';
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
            }
            install();
            new MutationObserver(install).observe(document.documentElement, { childList: true, subtree: false });
            document.addEventListener('DOMContentLoaded', install);
        })();
        """#
    }

    /// Watches for SPA changes, reports page state (login, share/model/menu controls),
    /// and exposes action helpers callable from Swift.
    private static var bridgeScript: String {
        #"""
        (function () {
            if (window.__cgptBridgeInstalled) { return; }
            window.__cgptBridgeInstalled = true;

            const HANDLER = '\#(messageHandlerName)';
            const LOGGED_IN_PROBE = '\#(loggedInProbe)';
            const LOGGED_OUT_PROBE = '\#(loggedOutProbe)';

            function post(body) {
                try { window.webkit.messageHandlers[HANDLER].postMessage(body); } catch (e) {}
            }

            // The web app persists the Appearance setting here ("light" / "dark" /
            // "system", sometimes JSON-quoted).
            function themePreference() {
                try {
                    return (localStorage.getItem('theme') || '').replace(/"/g, '').toLowerCase();
                } catch (e) {
                    return '';
                }
            }

            // Tags every position:sticky element in the sidebar with .cgpt-sticky
            // and toggles .cgpt-scrolled on the sidebar root while its scroll
            // container is scrolled, driving the frosted-header CSS.
            const SIDEBAR_ROOTS = ['\#(webSidebarSelectors.joined(separator: "', '"))'];
            function updateSidebarFrost() {
                let sidebar = null;
                for (const sel of SIDEBAR_ROOTS) {
                    sidebar = document.querySelector(sel);
                    if (sidebar) { break; }
                }
                if (!sidebar) { return; }
                let scroller = null;
                let frostBottom = 0;
                const sidebarRect = sidebar.getBoundingClientRect();
                sidebar.querySelectorAll('*').forEach(function (el) {
                    const cs = getComputedStyle(el);
                    if (cs.position === 'sticky') {
                        el.classList.add('cgpt-sticky');
                        frostBottom = Math.max(frostBottom, el.getBoundingClientRect().bottom);
                    }
                    if (!scroller && el.scrollHeight > el.clientHeight + 4
                        && /(auto|scroll|overlay)/.test(cs.overflowY)) {
                        scroller = el;
                    }
                });

                // One continuous frosted sheet from the sidebar top to the last
                // sticky row, instead of per-row backgrounds with gaps.
                let overlay = sidebar.querySelector('.cgpt-frost-overlay');
                if (frostBottom > 0) {
                    if (!overlay) {
                        overlay = document.createElement('div');
                        overlay.className = 'cgpt-frost-overlay';
                        sidebar.appendChild(overlay);
                    }
                    overlay.style.top = sidebarRect.top + 'px';
                    overlay.style.left = sidebarRect.left + 'px';
                    overlay.style.width = sidebarRect.width + 'px';
                    overlay.style.height = (frostBottom - sidebarRect.top) + 'px';
                } else if (overlay) {
                    overlay.remove();
                }

                if (scroller && !scroller.__cgptFrostBound) {
                    scroller.__cgptFrostBound = true;
                    const update = function () {
                        sidebar.classList.toggle('cgpt-scrolled', scroller.scrollTop > 2);
                    };
                    scroller.addEventListener('scroll', update, { passive: true });
                    update();
                }
            }
            window.addEventListener('resize', function () { setTimeout(updateSidebarFrost, 100); });

            function findSidebar() {
                for (const sel of SIDEBAR_ROOTS) {
                    const el = document.querySelector(sel);
                    if (el) { return el; }
                }
                return null;
            }

            // Some routes (Library, Projects, GPTs, the logged-out page) paint
            // their own opaque backgrounds on wrappers inside the sidebar that
            // the static CSS doesn't cover. Clear any large panel-sized fill so
            // the native glass always shows through, leaving small elements
            // (hover pills, selection highlights) alone.
            function clearSidebarBackgrounds() {
                const sidebar = findSidebar();
                if (!sidebar) { return; }
                const rect = sidebar.getBoundingClientRect();
                if (rect.width < 50) { return; }
                const nodes = [sidebar].concat(Array.from(sidebar.querySelectorAll('*')));
                for (const el of nodes) {
                    if (el.classList && el.classList.contains('cgpt-frost-overlay')) { continue; }
                    const r = el.getBoundingClientRect();
                    if (r.width < rect.width * 0.8 || r.height < rect.height * 0.5) { continue; }
                    const bg = getComputedStyle(el).backgroundColor;
                    if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)') {
                        el.style.setProperty('background-color', 'transparent', 'important');
                        el.style.setProperty('background-image', 'none', 'important');
                    }
                }
            }

            // The web app can boot with its sidebar collapsed or in the compact
            // icon rail. The app never shows those states: expand it via the
            // (CSS-hidden, but still clickable) open-sidebar button, unless the
            // user collapsed it natively (cgpt-hide-sidebar).
            let lastSidebarVisible = false;

            function ensureSidebarOpen() {
                if (document.documentElement.classList.contains('cgpt-hide-sidebar')) { return; }
                // Don't fight modal overlays (e.g. chat search): clicking the
                // open-sidebar button would dismiss them.
                if (document.querySelector('div[role="dialog"]')) { return; }
                // Windows that hide the sidebar on purpose (floating chats,
                // settings, aux panes) must not fight their own CSS.
                if (document.getElementById('cgpt-floating-style')
                    || document.getElementById('cgpt-settings-style')
                    || document.getElementById('cgpt-aux-style')) { return; }
                const sidebar = findSidebar();
                if (sidebar && sidebar.offsetWidth >= 100) { return; }
                const openButton = document.querySelector(
                    '[data-testid="open-sidebar-button"], button[aria-label*="open sidebar" i]'
                );
                if (openButton) { openButton.click(); }
            }

            let lastPayload = '';
            function report() {
                ensureSidebarOpen();
                clearSidebarBackgrounds();
                updateSidebarFrost();
                const loggedOut = !!document.querySelector(LOGGED_OUT_PROBE);
                const loggedIn = !loggedOut && !!document.querySelector(LOGGED_IN_PROBE);
                const shareButton = document.querySelector('\#(shareButtonSelector)');
                const modelButton = document.querySelector('\#(modelSwitcherSelector)');
                const menuButton = findConversationMenuTrigger();
                const modeButtons = findModeButtons();
                const selectedMode = modeButtons.find(isToggledOn);
                const tempChat = document.querySelector('\#(temporaryChatSelector)');
                // Detect dialogs that (almost) cover the viewport, tag them so the
                // CSS can stretch them, and let the native side clear its toolbar.
                const fullscreenDialog = (function () {
                    // The dedicated settings window classifies its own outer
                    // dialog; dialogs opened above it must remain modal sheets.
                    if (document.getElementById('cgpt-settings-style')) {
                        return false;
                    }
                    let found = false;
                    document.querySelectorAll('div[role="dialog"]').forEach(function (d) {
                        // The chat-search modal is a centered overlay, not a
                        // fullscreen takeover — leave it (and the sidebar) alone.
                        if (d.querySelector('input[placeholder*="search" i], [data-testid*="search" i]')) {
                            return;
                        }
                        const r = d.getBoundingClientRect();
                        if (r.width >= innerWidth * 0.85 && r.height >= innerHeight * 0.75) {
                            d.classList.add('cgpt-fullscreen-dialog');
                            found = true;
                        }
                    });
                    return found;
                })();
                const state = {
                    type: 'state',
                    loggedIn: loggedIn,
                    path: location.pathname,
                    title: document.title || '',
                    canShare: !!shareButton,
                    model: modelButton ? (modelButton.textContent || '').trim() : '',
                    hasConversationMenu: !!menuButton,
                    modes: modeButtons.map(function (b) { return (b.textContent || '').trim(); }),
                    selectedMode: selectedMode ? (selectedMode.textContent || '').trim() : '',
                    hasTemporaryChat: !!tempChat,
                    temporaryChatActive: (tempChat && isToggledOn(tempChat))
                        || location.search.includes('temporary-chat=true'),
                    appearance: themePreference(),
                    fullscreenDialogOpen: fullscreenDialog,
                    sidebarVisible: (function () {
                        // While a modal (e.g. chat search) is up the web app may
                        // hide the sidebar underneath; keep reporting the last
                        // real state so the native glass doesn't flicker away.
                        if (document.querySelector('div[role="dialog"]')) {
                            return lastSidebarVisible;
                        }
                        for (const sel of SIDEBAR_ROOTS) {
                            const el = document.querySelector(sel);
                            if (el) { return lastSidebarVisible = el.offsetWidth > 50; }
                        }
                        return lastSidebarVisible = false;
                    })(),
                };
                const payload = JSON.stringify(state);
                if (payload !== lastPayload) {
                    lastPayload = payload;
                    post(state);
                }
            }

            let scheduled = null;
            function scheduleReport() {
                if (scheduled) { return; }
                scheduled = setTimeout(function () { scheduled = null; report(); }, 300);
            }

            new MutationObserver(scheduleReport).observe(document.body || document.documentElement, {
                childList: true,
                subtree: true,
                characterData: true,
            });

            // SPA route changes don't always mutate the sidebar; hook history too.
            for (const fn of ['pushState', 'replaceState']) {
                const original = history[fn];
                history[fn] = function () {
                    if (arguments.length > 2) {
                        const tab = settingsTabForValue(String(arguments[2] || ''));
                        if (tab && !document.querySelector(LOGGED_OUT_PROBE)) {
                            post({ type: 'openSettings', tab: tab });
                            scheduleReport();
                            return;
                        }
                    }
                    const result = original.apply(this, arguments);
                    scheduleReport();
                    return result;
                };
            }
            window.addEventListener('popstate', scheduleReport);
            window.addEventListener('hashchange', function () {
                const tab = settingsTabForValue(location.hash || '');
                if (tab && !document.querySelector(LOGGED_OUT_PROBE)
                    && !document.getElementById('cgpt-settings-style')) {
                    post({ type: 'openSettings', tab: tab });
                }
                scheduleReport();
            });
            setInterval(report, 3000);
            report();

            // Route the profile menu's Settings / Personalization items to the
            // native settings window instead of the inline web dialog. Different
            // routes render the account menu with different roles/labels, so use
            // hrefs and accessible labels in addition to visible text.
            function controlLabel(el) {
                return (
                    el.getAttribute('aria-label')
                    || el.getAttribute('title')
                    || el.textContent
                    || ''
                ).trim().replace(/\s+/g, ' ').toLowerCase();
            }

            function settingsTabForValue(value) {
                const text = (value || '').toLowerCase();
                if (text.indexOf('personalization') !== -1) { return 'personalization'; }
                if (text.indexOf('settings') !== -1) { return 'settings'; }
                return '';
            }

            function settingsTabForControl(el) {
                const label = controlLabel(el);
                const href = el.getAttribute('href') || '';
                const tab = settingsTabForValue(href + ' ' + label);
                if (tab) { return tab; }
                if (label === 'settings'
                    || label.startsWith('settings ')
                    || label.indexOf(' settings') !== -1) {
                    return 'settings';
                }
                return '';
            }

            document.addEventListener('click', function (e) {
                if (document.getElementById('cgpt-settings-style')) { return; }
                if (!e.target || !e.target.closest) { return; }
                const item = e.target.closest(
                    '[role="menuitem"], [role="menuitemradio"], [role="option"], '
                    + '[data-testid*="settings" i], button, a[href]'
                );
                if (!item || item.closest('div[role="dialog"]')) { return; }
                const tab = settingsTabForControl(item);
                if (!tab) { return; }
                // Logged out, the site's own settings popover is used instead
                // of the native window.
                if (document.querySelector(LOGGED_OUT_PROBE)) { return; }
                e.preventDefault();
                e.stopImmediatePropagation();
                post({ type: 'openSettings', tab: tab });
                document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
            }, true);

            // --- Helpers called from Swift ---

            // The home screen's "Chat / Work" switcher: header buttons/tabs whose
            // whole label is one of the mode names.
            function findModeButtons() {
                const header = document.querySelector('#page-header');
                if (!header) { return []; }
                return Array.from(header.querySelectorAll('button, [role="tab"], [role="radio"]'))
                    .filter(function (b) {
                        const t = (b.textContent || '').trim();
                        return t === 'Chat' || t === 'Work';
                    });
            }

            function isToggledOn(el) {
                return el.getAttribute('aria-checked') === 'true'
                    || el.getAttribute('aria-selected') === 'true'
                    || el.getAttribute('aria-pressed') === 'true'
                    || el.getAttribute('data-state') === 'active'
                    || el.getAttribute('data-state') === 'checked'
                    || el.getAttribute('data-state') === 'on';
            }

            window.__cgptSelectMode = function (name) {
                const target = findModeButtons().find(function (b) {
                    return (b.textContent || '').trim() === name;
                });
                if (target) { target.click(); scheduleReport(); return true; }
                return false;
            };

            // Collapse the sidebar by hiding it directly (CSS class on <html>),
            // rather than relying on the web app's own toggle buttons, whose
            // markup changes too often to click reliably.
            window.__cgptToggleSidebar = function () {
                document.documentElement.classList.toggle('cgpt-hide-sidebar');
                report();
                return true;
            };

            window.__cgptToggleTemporaryChat = function () {
                const button = document.querySelector('\#(temporaryChatSelector)');
                if (button) { button.click(); scheduleReport(); return true; }
                return false;
            };

            function findConversationMenuTrigger() {
                const direct = document.querySelector('\#(conversationMenuSelector)');
                if (direct) { return direct; }
                // Fallback: last menu-popup button in the header that isn't the model switcher.
                const candidates = Array.from(document.querySelectorAll(
                    '#page-header button[aria-haspopup="menu"], #conversation-header-actions button[aria-haspopup="menu"]'
                )).filter(function (b) { return !b.matches('\#(modelSwitcherSelector)'); });
                return candidates.length ? candidates[candidates.length - 1] : null;
            }

            // Programmatic .click() still fires React handlers on display:none elements,
            // so the hidden header buttons keep working as native toolbar backends.
            window.__cgptShare = function () {
                const button = document.querySelector('\#(shareButtonSelector)');
                if (button) { button.click(); return true; }
                return false;
            };

            // `centered` repositions the dropdown under the window's horizontal
            // center: the menu is a popper anchored to the hidden web header
            // button (top-left), but the native button that opens it is centered
            // in the toolbar when logged out. Re-applies for a few frames since
            // the popper sets its own transform asynchronously.
            window.__cgptOpenModelMenu = function (centered) {
                const button = document.querySelector('\#(modelSwitcherSelector)');
                if (!button) { return false; }
                // Second click on the native button closes the open menu.
                if (button.getAttribute('aria-expanded') === 'true'
                    || button.getAttribute('data-state') === 'open') {
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                    return true;
                }
                button.click();
                if (centered) {
                    let tries = 0;
                    const timer = setInterval(function () {
                        tries++;
                        if (tries > 20) { clearInterval(timer); return; }
                        const wrapper = document.querySelector('[data-radix-popper-content-wrapper]');
                        if (!wrapper) { return; }
                        const width = wrapper.getBoundingClientRect().width;
                        const x = Math.round((innerWidth - width) / 2);
                        wrapper.style.setProperty('transform', 'translate(' + x + 'px, 8px)', 'important');
                    }, 30);
                }
                return true;
            };

            // Opens the (hidden) conversation options dropdown, waits for its items to
            // render in the portal, then clicks the one matching `label`. Prefers an
            // exact text match so "Pin chat" doesn't accidentally hit "Unpin chat".
            window.__cgptMenuAction = function (label) {
                const trigger = findConversationMenuTrigger();
                if (!trigger) { return false; }
                trigger.click();
                const wanted = label.toLowerCase();
                let attempts = 0;
                const timer = setInterval(function () {
                    attempts++;
                    const items = Array.from(document.querySelectorAll('[role="menuitem"]'));
                    const texts = items.map(function (i) { return (i.textContent || '').trim().toLowerCase(); });
                    let index = texts.indexOf(wanted);
                    if (index < 0) {
                        index = texts.findIndex(function (t) { return t.includes(wanted); });
                    }
                    if (index >= 0) {
                        clearInterval(timer);
                        items[index].click();
                    } else if (attempts > 20) {
                        clearInterval(timer);
                        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                    }
                }, 50);
                return true;
            };

            // Scales only the chat surface via CSS zoom on <main>; the sidebar
            // and page chrome keep their normal size.
            window.__cgptSetTextZoom = function (scale) {
                var style = document.getElementById('cgpt-text-zoom');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'cgpt-text-zoom';
                    (document.head || document.documentElement).appendChild(style);
                }
                style.textContent = (!scale || scale === 1)
                    ? ''
                    : 'main { zoom: ' + scale + ' !important; }';
                return true;
            };

            window.__cgptNewChat = function () {
                const target = document.querySelector(
                    '[data-testid="create-new-chat-button"], a[data-testid="new-chat-button"], nav a[href="/"]'
                );
                if (target) { target.click(); scheduleReport(); return true; }
                return false;
            };
        })();
        """#
    }
}

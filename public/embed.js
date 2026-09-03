/**
 * GameAll booking embed.
 *
 * A club drops one line into their own website and gets the booking flow
 * inline, sized to its content:
 *
 *   <script src="https://<host>/embed.js" data-facility="<facilityId>"></script>
 *
 * The script inserts an iframe where it sits. Optional attributes:
 *
 *   data-target="#some-element"   render into that element instead
 *   data-sport="<facilitySportId>" preselect a sport
 *   data-height="900"              starting height before the first
 *                                  auto-size message arrives
 *
 * Deliberately dependency-free and framework-agnostic: it has to run on
 * WordPress, Wix, Squarespace and hand-written HTML alike.
 */
(function () {
  "use strict";

  var script = document.currentScript;
  if (!script) return;

  var facilityId = script.getAttribute("data-facility");
  if (!facilityId) {
    // Misconfiguration is worth saying out loud — silently rendering nothing
    // is the hardest kind of embed to debug from the club's side.
    if (window.console && console.error) {
      console.error("[GameAll] embed.js needs a data-facility attribute.");
    }
    return;
  }

  var origin = new URL(script.src, window.location.href).origin;
  var sport = script.getAttribute("data-sport");
  var initialHeight = parseInt(script.getAttribute("data-height") || "", 10) || 820;

  // Straight to the flow: the host page is already the venue's front door,
  // so the landing step would only repeat what surrounds the widget.
  var src = origin + "/book/" + encodeURIComponent(facilityId) + "/booking?embed=1";
  if (sport) src += "&sport=" + encodeURIComponent(sport);

  var iframe = document.createElement("iframe");
  iframe.src = src;
  iframe.title = "Book a court";
  iframe.loading = "lazy";
  iframe.setAttribute("allow", "clipboard-write");
  iframe.style.width = "100%";
  iframe.style.border = "0";
  iframe.style.display = "block";
  iframe.style.height = initialHeight + "px";
  // Transitioning height keeps step changes from snapping the host page.
  iframe.style.transition = "height 180ms ease";

  var targetSelector = script.getAttribute("data-target");
  var target = targetSelector ? document.querySelector(targetSelector) : null;
  if (target) {
    target.appendChild(iframe);
  } else if (script.parentNode) {
    script.parentNode.insertBefore(iframe, script.nextSibling);
  } else {
    document.body.appendChild(iframe);
  }

  window.addEventListener("message", function (event) {
    // Only trust height messages from the frame we created.
    if (event.origin !== origin) return;
    if (event.source !== iframe.contentWindow) return;

    var data = event.data;
    if (!data || data.type !== "gameall:height") return;

    var height = Number(data.height);
    if (!isFinite(height) || height <= 0) return;

    iframe.style.height = Math.ceil(height) + "px";
  });
})();

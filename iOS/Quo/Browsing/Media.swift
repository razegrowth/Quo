import AVFoundation
import UIKit

/// Video and sound on pages: Picture in Picture, and playing on when you
/// leave Quo, as a music app does.
///
/// Leaving Quo hides its pages, and many sites stop their video or music
/// as soon as the page says it's hidden. With "Keep playing when you leave
/// Quo" on, pages are never told they're hidden, and whatever WebKit itself
/// paused on the way out is started again; the app is allowed to play in
/// the background (UIBackgroundModes: audio), and its sound is played as
/// playback, so the silent switch doesn't mute a video.
@MainActor
enum Media {
    /// Sound as playback: what a page plays is heard with the silent switch
    /// on, and goes on in the background. Setting it starts nothing; the
    /// session only becomes active when a page plays.
    static func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { leaving() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { left() }
        }
    }

    private static func leaving() {
        guard AppSettings.shared.playsInBackground else { return }
        for tab in Tabs.shared.all where tab.isBuilt { tab.noteMedia() }
    }

    private static func left() {
        guard AppSettings.shared.playsInBackground else { return }
        // Twice: WebKit pauses as the app goes, and again once it's gone.
        for delay in [0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for tab in Tabs.shared.all where tab.isBuilt { tab.resumeMedia() }
            }
        }
    }

    /// In every page at its start: tells the app it has a video, and with
    /// `keepPlaying`, never lets the page see itself hidden.
    static func script(keepPlaying: Bool) -> String {
        """
        (function(){
          if (window.__quoMedia) return;
          window.__quoMedia = true;
          if (\(keepPlaying ? "true" : "false")) {
            try {
              var visible = function(name, value){
                Object.defineProperty(document, name, {get: function(){ return value; }, configurable: true});
              };
              visible('hidden', false);
              visible('webkitHidden', false);
              visible('visibilityState', 'visible');
              visible('webkitVisibilityState', 'visible');
              var hush = function(e){ e.stopImmediatePropagation(); };
              ['visibilitychange', 'webkitvisibilitychange'].forEach(function(name){
                window.addEventListener(name, hush, true);
                document.addEventListener(name, hush, true);
              });
            } catch (e) {}
          }
          var told = false;
          var tell = function(e){
            if (told || !e.target || e.target.tagName !== 'VIDEO') return;
            told = true;
            try { window.webkit.messageHandlers.quoMedia.postMessage({video: true}); } catch (x) {}
          };
          document.addEventListener('loadedmetadata', tell, true);
          document.addEventListener('play', tell, true);
        })();
        """
    }

    /// Marks what's playing as the app goes.
    static let note = """
    (function(){
      document.querySelectorAll('video, audio').forEach(function(m){ m.__quoWas = !m.paused && !m.ended; });
      return true;
    })();
    """

    /// Plays on whatever was playing and has been paused since.
    static let resume = """
    (function(){
      var n = 0;
      document.querySelectorAll('video, audio').forEach(function(m){
        if (m.__quoWas && m.paused && !m.ended) { n++; var p = m.play(); if (p && p.catch) p.catch(function(){}); }
      });
      return n;
    })();
    """

    /// The page's video into Picture in Picture or back: "in", "out",
    /// "none" for a page without one, "no" for one that can't.
    static let pictureInPicture = """
    (function(){
      var all = Array.prototype.slice.call(document.querySelectorAll('video'));
      if (!all.length) return 'none';
      var area = function(v){ var r = v.getBoundingClientRect(); return r.width * r.height; };
      var v = all.filter(function(x){ return !x.paused; })[0] || all.sort(function(a, b){ return area(b) - area(a); })[0];
      if (v.webkitPresentationMode === 'picture-in-picture') { v.webkitSetPresentationMode('inline'); return 'out'; }
      v.disablePictureInPicture = false;
      v.removeAttribute('disablepictureinpicture');
      if (!v.webkitSupportsPresentationMode) return 'no:api';
      if (!v.webkitSupportsPresentationMode('picture-in-picture')) return 'no:unsupported';
      if (v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
        v.webkitSetPresentationMode('picture-in-picture');
        if (v.paused) { var p = v.play(); if (p && p.catch) p.catch(function(){}); }
        return 'in';
      }
      if (v.requestPictureInPicture) { v.requestPictureInPicture().catch(function(){}); return 'in'; }
      return 'no';
    })();
    """
}

/* Pure timeline operations used by HOTICE's browser-local editor.
   No file access, remote calls or user data storage. */
(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.HoticeTimelineCore = api;
  }
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';

  function moveClip(clips, from, step, activeIndex) {
    if (!Array.isArray(clips) ||
        !Number.isInteger(from) ||
        !Number.isInteger(step) ||
        !Number.isInteger(activeIndex)) {
      throw new TypeError('Invalid timeline arguments');
    }
    const to = from + step;
    if (from < 0 || from >= clips.length ||
        to < 0 || to >= clips.length) {
      return activeIndex;
    }
    const current = clips[activeIndex] || null;
    const [moved] = clips.splice(from, 1);
    clips.splice(to, 0, moved);
    // Keep editing the originally selected clip, even when another
    // clip was reordered past it.
    return current === null ? -1 : clips.indexOf(current);
  }

  return Object.freeze({moveClip});
});

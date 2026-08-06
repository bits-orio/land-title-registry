-- Land Title Registry's own sound prototypes, referencing base-game audio files (no
-- third-party assets). Custom recordings can replace the filenames later
-- without touching any play_sound call site.
data:extend({
  {
    type = "sound",
    name = "ltr-sound-claim",
    filename = "__core__/sound/build-medium.ogg",
    volume = 0.7,
  },
  {
    type = "sound",
    name = "ltr-sound-deny",
    filename = "__core__/sound/cannot-build.ogg",
    volume = 0.8,
  },
  {
    type = "sound",
    name = "ltr-sound-refund",
    filename = "__core__/sound/deconstruct-medium.ogg",
    volume = 0.7,
  },
})

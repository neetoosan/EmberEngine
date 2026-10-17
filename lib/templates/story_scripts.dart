/// The story and scripts of "The Last Ember" (a visual novel made with the
/// Story Player). All of it is editable in the Script workspace.
const Map<String, String> storyScripts = {
  'the_last_ember.story': _story,
  'story_title.ember': _title,
  'story_effects.ember': _effects,
};

const _story = r'''
# The Last Ember: a short visual novel. Edit it freely; changes show while playing.
# Lines are "who: text" or "who expression: text"; plain lines are narration.
# Commands: scene, show, hide, music, sound, set, if ... jump, choice, wait, event, end.

@title The Last Ember
@background forge   assets/templates/story/forge.png
@background village assets/templates/story/village.png
@background hill    assets/templates/story/hill.png
@background dawn    assets/templates/story/dawn.png
@character mira "Mira" #F59E0B assets/templates/story/mira.png neutral happy sad surprised
@character kai  "Kai"  #60A5FA assets/templates/story/kai.png  neutral happy sad surprised
@var trust = 0
@var secret = false
@var stars = false

label start:
music assets/templates/story/theme.wav 0.35
scene forge fade
The great forge of Emberfall has burned for three hundred years.
Tonight, for the first time, its fire is going out.
show mira sad center
mira sad: Come on... just a little longer. Master Bram never let you go cold.
sound hit 0.5
Someone knocks at the door. Three slow knocks, then silence.
mira surprised: At this hour? In this storm?
choice:
  * Open the door {trust += 1} -> open
  * Ask who it is first -> ask
  * Tell them to go away {trust -= 1} -> refuse

label open:
mira: Come in, quickly, before the wind takes the roof!
show mira neutral left
show kai neutral right
kai happy: Thank you. Most doors in this town stayed shut.
jump arrival

label ask:
mira: Who's there? Say your name!
"A voice": A traveller with a lantern and no roof. My name is Kai.
show mira neutral left
show kai neutral right
kai: I won't stay long. I only need to see your fire.
jump arrival

label refuse:
mira: The forge is closed. Go find an inn!
"A voice": There is no inn that can help me. Please. It is about your fire.
show mira surprised left
show kai sad right
kai sad: I saw it from the hill. It's dying, isn't it?
jump arrival

label arrival:
Kai's lantern burns with a *blue* flame. It throws no smoke and makes no sound.
mira surprised: What kind of fire is that?
kai: The ember of the north. It never goes out, but it cannot shape iron.
kai: I need a blade forged in an old fire. Yours is the oldest I have found.
mira sad: Then you're too late. Since Master Bram died, nothing I do keeps it alive.
kai: My ember could feed it. Your fire for my blade. A fair trade?
choice:
  * Show him the forge's heart {trust += 2} -> heart
  * Ask him about the north {trust += 1} -> north
  * "I don't need your help." -> pride

label heart:
set secret = true
mira: Bram made me promise never to show anyone this. But you should see it.
Behind the furnace, a stone with a single glowing crack: the heart of the forge.
kai surprised: It's still warm. It isn't dead at all. It's waiting.
jump market

label north:
mira: What is the north like? Is it true the snow never melts?
kai happy: It's true. But the sky there burns green at night. I'd show you, one day.
jump market

label pride:
mira: I'll save this forge myself. I don't need a stranger's magic.
kai sad: I understand. But I'll wait until morning, if you'll let me.
jump market

label market:
scene village fade
show mira neutral left
show kai neutral right
By dusk the storm has passed. They walk to the market for the last of the coal.
if trust >= 2 jump story
mira: Let's be quick. People stare at strangers here.
jump hilltop

label story:
kai: When I was small, my village lost its fire too. Nobody knew how to bring it back.
kai sad: I've been looking for someone who does ever since.
mira: Then maybe we're looking for the same thing.
jump hilltop

label hilltop:
scene hill fade
show mira neutral left
show kai neutral right
On the way back, the path climbs the hill above the town. The stars are out.
choice:
  * Stop and look at the stars together {trust += 1} -> starlight
  * Hurry back to the forge -> hurry

label starlight:
set stars = true
mira happy: Look, *there*, the bright one. Bram called it the Smith's Star.
kai happy: In the north we call it the Lantern. It always points home.
jump relight

label hurry:
mira: No time. The coals won't last the night.
jump relight

label relight:
scene forge fade
show mira neutral left
show kai neutral right
Kai opens his lantern. The blue flame leans toward the furnace, as if it knew the way.
event relight
wait 0.6
if trust >= 4 and secret and stars jump northern_star
if trust >= 3 jump two_flames
if trust >= 1 jump wanderer
jump cold_iron

label northern_star:
mira happy: It's catching! Blue and gold, together!
kai surprised: The heart... it's answering the Lantern star.
scene dawn fade
show mira happy left
show kai happy right
By morning the forge burns brighter than it has in a hundred years, and a new blade cools on the anvil.
kai happy: I came here for a sword. I think I found an apprentice's seat instead. If you'll have me.
mira happy: The forge could use two smiths. And I'd like to see that green sky one day.
end The Northern Star (secret ending)

label two_flames:
mira happy: It's working! The fire's coming back!
scene dawn fade
show mira happy left
show kai happy right
At dawn, Kai leaves with a blade still warm from the forge, and promises to visit every winter.
mira happy: Two flames, one fire. Come back soon, Kai.
end Two Flames, One Fire

label wanderer:
mira: It's burning again... but only just.
scene dawn fade
show mira neutral left
show kai neutral right
kai: It will hold, if you tend it every day. I'll find my blade somewhere else.
hide kai
Mira watches the road until the blue light is gone over the hill.
end The Wanderer's Road

label cold_iron:
The blue flame circles the furnace once, then fades back into the lantern.
kai sad: I'm sorry. It needs to be invited. I don't think I was.
hide kai
mira sad: ...
The last coal goes dark. Outside, the snow begins.
end Cold Iron
''';

const _title = r'''
// Title screen: new story, continue (the autosave), or load a saved slot.
void onStart() {
  var canContinue = loadValue("lastember_auto", null) != null;
  find("ContinueButton").enabled = canContinue;
  var found = loadValue("lastember_endings", null);
  var count = found == null ? 0 : found["names"].length;
  setText("EndingsText", "Endings found: $count / 4");
  playMusic("assets/templates/story/theme.wav", 0.3);
}

void onUIAction(action) {
  if (action == "new") Game.data["storyLoad"] = "";
  if (action == "continue") Game.data["storyLoad"] = "auto";
  if (action == "load") Game.data["storyLoad"] = "menu";
  if (action == "new" || action == "continue" || action == "load") loadLevel("Story");
}
''';

const _effects = r'''
// Reacts to "event" lines in the story.
void onStoryEvent(name) {
  if (name == "relight") {
    playSound("explosion", volume: 0.35);
    playSound("coin", volume: 0.4, pitch: 0.7);
  }
}
''';

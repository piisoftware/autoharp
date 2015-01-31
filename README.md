<h1>AUTOHARP</h1>
<h3>by Paul Mariz - paul@piisoftware.com</h3>

Hello there! This is AutoHarp. AutoHarp is a (somewhat) programmable music-generating suite written in Perl. This document assumes cursory knowledge of music theory, a fair degree of technical ability (you are comfortable with your computer’s command line and, if you want to use the deeper abilities of this program, you know what JSON is), and that you have some use for MIDI files once you generate them.

  

This is by no means complete documentation of this software. That would span hundreds of pages and be woefully incomplete. In many cases I have no idea what the expected behavior of a particular thing is. Be a tinkerer. Try things out. 

This software is (c) 2015 by Paul Mariz/Pii Software.It is distributed under the GNU GPL-3.0 license (see LICENSE)--you may derive from this code but it must be released under the same license. This license also explicitly applies to all music generated: it is yours to do with as you will, so long as you credit the source (the AutoHarp program and its author(s)), and extend the same rights going forward (e.g. you agree to allow other musicians to sample your work). HOWEVER, this does not extend to already copyrighted material. <b>If you import copyrighted files or copyrighted melodies (or anything else carrying copyright) while using AutoHarp, it is your responsibility to fulfill any requirements with the copyright holder prior to publishing any derived music.</b> 

This is version 0.1.5.

Today is 30 January 2015

<h3>WHAT IS AUTOHARP?</h3>

AutoHarp is a collection of tools that machine-generate music in the form of MIDI files. Once it’s set up and seeded (see below), you can run it knowing nothing whatsoever about music or technology and it will generate music for you. If you can plumb the depths of the JSON files it generates and uses as input, you will be able to program your own melodies and chord progressions, song structures, and instrumentation. This program is intended for users of Digital Audio Workstations--generate a song, import it into a DAW, and muck with it from there as you see fit. Move stuff around, choose new MIDI instruments for the tracks, play along with real instruments, write lyrics and sing them, etc.  

  

<h3>HOW DOES IT WORK?</h3> 

Honest to God, I have no idea. It kind of just does. I wrote it and then A Miracle Occurred in Step 2. You could look at the code, but I don’t think it would really help you to understand. 

<h3>IN ORDER TO USE THIS SOFTWARE</h3>

- You will need Perl version 5.14 or above, and working CPAN (i.e. you can get and build perl modules from the CPAN repository). On OS X you can install the command-line developer tools from [http://developer.apple.com/download](http://developer.apple.com/download). On Windows, the installation has been tested with Strawberry Perl [http://strawberryperl.com](http://strawberryperl.com) by Tim at Letter Seventeen (Thanks Tim!). On Linux you should be good to go, because you’re a GODDAMN LINUX USER, MOTHERFUCKERS.    
- You will want (but not absolutely need) a command-line MIDI player, such as timidity or qtplay. This allows you to audition output as soon as it’s generated, which makes the music generating workflow much faster. Google around to find what’s available on your system. You will also need a soundfont (a collection of sound files that map MIDI patches to actual sounds).  
- You will unzip this software into a directory you have read/write access to, cd into that directory, and run "./configure" (or "perl configure" if you must). 
- You will need to "seed" the program with a variety of MIDI drum loops. See immediately below this line. 

<h3>SEEDING THE SOFTWARE</h3>

- AutoHarp cannot brain by itself. It has the dumb and needs a repository of MIDI drum loops in order to do anything interesting (PRO TIP: Google "Free MIDI drum loops" to find some). In order to add them, run the "import" tool found in this package.

<code>&gt;import /directory/where/your/loops/are</code>

- It will probably ask you for the name of a musical genre under which to file each loop unless (PRO TIP again) your loops are sorted into directories named for the genre they belong in.   
    - Example: if your Hip Hop loops are in a directory called "hiphop" (case and spacing don’t matter) and the first time it asks you what genre they are you type "Hip Hop", it'll magically* sort the rest of them. 
    - You can also name the files (or subdirectories they’re in) with things like “verse”, “chorus”, “fill,” and the program will categorize them appropriately.
- PRO TIP again, again: The more, and more varied, loops you import, the more interesting AutoHarp gets. Author and import your own! You will be extra cool. Note the warning about copyright above. Taking a copyrighted loop and importing it into this program does not make in un-copyrighted. Diddy will still sue you. 
<pre>*not actual magic</pre>

<h3>OKAY, NOW LET'S MAKE SOME MUSIC</h3>

Generate a song:

  <code>./generate &lt;optional genre name&gt;</code>
  
- set the environment variable AUTOHARP_QUIET=omfgyes (or anything true) to be less chatty. 
- set the environment variable MIDI_PLAYER to the name of your MIDI player if you have one and didn't specify it during the "./configure" stage (you can also just run configure again safely). 
- Omit the genre name and AutoHarp will choose from one that it knows. Type in a bunk genre name to get a list of valid ones. 
  
Output of this song will be one MIDI file and one JSON file. Their locations will be printed. If your player has been set the midi file will now play for your pleasure. Peruse the JSON file to see the key, chord progressions, and other data about the song.

Regenerate a song:

  <code>./regenerate &lt;a JSON file, either from the program or the user&gt;</code>
  
The JSON file output by the program can be altered and run again. Different things will happen. For more information on this, do not stop reading at the end of this section, but instead continue to read.

One other handy tool:

  <code>./shiftPitch &lt;path to midi file&gt; &lt;number of half steps&gt;</code>

Shift a given midi file up or down a given number of half steps. e.g. 
<code>shiftPitch eFlat.midi -3</code> will take a MIDI file that starts in E Flat and put it into a starting key of C. 

<h3>PROGRAMMING AUTOHARP</h3>

Here it gets a bit technical. But also cool. Weigh your (possible lack of) technical knowledge against your desire for cool when deciding whether to continue reading. Have you decided? Good. Let us continue.

- You (yes, you) can exercise control over the chords and melodies of the song parts that AutoHarp plays.
- You (yes, you) can also exercise control over the MIDI patches and instrument types that play during a song.
- You (blah blah) can also also exercise control over what sequence the song is played in, and which instruments play when.
- As to what the instruments actually play, you are powerless. POWERLESS I SAY (at least in this version. Maybe next time).

The way in which you do this is both complicated to explain, but somewhat self-explanatory if you look at one of these files. There are several examples in the "scaffolds" directory. Go look at "full.json", for instance. Go ahead, I'll wait….

Full.json is a file in which pretty much everything is specified. If you run it many times, the results will be pretty similar every time. Go ahead and run that file through the regenerate program, and you will hear a version of a song that will be familiar unless you lived under a rock during 2011. 

Look now at "fromHook.json" and "fourChords.json". These contain very little information. The regenerate program will fill the rest of it in at run time. Try running both of these now. Note that the results, while similar, are much more varied than what you get from running full.json many times.   

Any questions? Yes, there in the back?

Q: Yeah, uh...how the fuck do I PROGRAM ANYTHING AT ALL?

A: I'm glad you asked that. The best thing to do is generate a song first and then look at the JSON output. 

Here's the chorus for a song I just generated:

<code><pre>"chorus" : [
    "meter: 4/4, tempo: 93, swingPercentage: 9, swingNote: sixteenth, key: B Flat, genre: Big Easy",
    "|A# / / /|Gm / / /|D# / / /|A# / / /|A# / / /|Gm / / /|D# / / /|A# / / /|",        
    "|_b/2_b'/2f'/2d'/2d'/2_b/2_b/4f'/2f'/4|g/2G/2c/2_e/2_e/2g/2g/4c/2c/4|_e/2_E/2A/2c/2c/2_e/2_e/4A/2A/4|_b/2_B/2_e/2g/2g/2_b/2_b/4_e/2_e/4|_b/2_b'/2f'/2d'/2d'/2_b/2_b/4f'/2f'/4|g/2G/2c/2_e/2_e/2g/2g/4c/2c/4|_e/2_E/2A/2c/2c/2_e/2_e/4A/2A/4|_b/2_B/2_e/2g/2g/2_b/2_b/4_e/2_e/4|"
],</pre></code>

A musical element (like a chorus or a verse) in autoharp is a three (or more) element array:

- LINE 1: meter/key/tempo. Pretty straightforward (See that stuff about swing? Ignore it. It doesn't do shit. I couldn't get it to work. If there is swing in your drum loops, there'll be swing in your song). Key will actually be ignored if there's a chord progression. Musical elements (verse, bridge, chorus) have chord progressions in the next line, hooks do not (see the hooks section below). Note you can also specify the genre here. 
    - IMPORTANT CAVEAT: You can only play in meter/genre combinations for which you have at least one drum loop. If you specify Hip Hop and 5/4 time, and you haven’t imported a 5/4 Hip Hop loop, the program will explode*.  
- LINE 2: Chord progression. |'s denote bar markers, so the chorus above is 8 measures. 
    - AutoHarp really likes 8 measure things. Just FYI. You can make yours shorter or longer, but that's what it does when it lacks other information.  
    - AutoHarp is quasi-smart about chord names. You should be able to type things like "G#flat9 over D" and get a chord out of it. 
        - Don’t use the common notation “G/B” for G over B. ”G/B” is two beats of G and one beat of B--see below.  
        - It uses "#" and "b" (that's a small ‘B’) to specify sharp and flat when speaking about notes, and the words “sharp” and “flat” when speaking about intervals. So “Bb9” is a Bb major triad with a ninth, and “Bflat9” is a B major triad with a C in it. Which is a weird-ass chord. MIDI itself is well-tempered, so I had to kind of jury-rig the whole flat/sharp thing.   
        - I haven't tested every possible way to spell a chord. If you enter something it can’t parse, it’ll scream at you** to try again.   
    - A "/" represents a beat (whatever the note of the beat is, e.g. quarter note in 4/4), a "." represents a quarter of that beat, and the chord spelling itself represents exactly one of whatever it's next to.  
    - e.g. the verse chords to "Billie Jean" (which is syncopated) would be <code>|Em.....F#min over E. / /|G over D.....F#min over E. / /|</code> repeated. 
    - If you write out a chord measure without the correct number of beats in it, the program will self-destruct***. 
- LINE 3: A melody, written in ABC Music Notation. 

Q: ABC Whatnow?

A: ABC Notation. It's a way of writing melodies in text. Use The Google. It's what this program uses as a simple way to export melodies to readable data. If this program gets a GUI someday, that'll certainly change. It may or may not be worth your time to learn, though it is fairly straightforward. One key difference between our implementation and the canonical one is that we don’t bother with flat/sharp/natural vis-a-vis key. An A flat is always written ‘_a’, an A sharp is always ‘^a’, and an A natural is ‘a’ no matter what key we’re in. 

Q: Is there something I could look at that would give me a basic example?

A: Yes--look again at “fromHook.json” in the scaffolds directory. You’ll know the tune it’s playing (assuming you ran it through the regenerator before), so that might give you that extra bit of understanding you were...can I just say be-tee-dubs that I just fed the chords to Billie Jean (just to make sure I was correct about the notation above) into the program while I was writing this? And that I'm listening now? And it's kind of cool? I’ve just added it to the scaffolds directory.

Q: That’s great, I’m really happy for you. You were saying about ABC Notation?

A: Oh right: 

- LINE 4 or higher, if present: more melodies. ABC Notation only allows for one note at a time, so if the melody generated happens to have harmonies or overlapping notes, the program will split them into multiple ABC Notation lines. That’s also how you can add a harmonized melody if you’re just that much of a badass. 
- In a given song, you might not actually ever hear the melody (though the instrumentation will be influenced by what the melody is). If you want to hear your melodies in a song, add a melody theme to your instrument list (see the instruments section below). 
  
Q: I think I’m starting to understand a little. If I have four chords, and I want to create a song from them, or I have a simple melody and I want a song from that, I can make a copy of the appropriate file from the scaffolds directory and type in my music. I could probably do that even if I didn’t know anything about the JSON format (which I totally do, by the way, I’m not saying I don’t). 

A: That’s right; you do need to be careful about commas and squiggly brackets and things--JSON is kind of a stickler for syntax, AutoHarp is a stickler for the format of the data itself, and if you mess up the format the program will cause all life as you know it to stop instantaneously and every molecule in your body to explode at the speed of light****. But otherwise...there is knowledge to be had by reading program output and much experimenting to be done. You can fill in as much or as little as you want and AutoHarp will generate whatever is missing. You can generate a song, then decide that you wish the chords were slightly different or that the melodies suck, change them or delete them (causing the program to generate new ones), and run regenerate on the file to get something new (make sure to delete your trailing commas. Those always trip me up). You might get weird results. Maybe the weird results will be good. 

<pre> *not literally explode
 **not actually scream
 ***not really self-destruct
 ****Total Protonic Reversal. This will totally happen. Don’t cross the streams.</pre>
  
<h3>THE HOOK</h3>

The hook is a simple melody; observe that it stands in its own section in the JSON file and has no chord progression. It’s usually just two lines. Let’s look at the one from “fromHook.json”:

<code><pre>"hook" : [
  "meter: 4/4, tempo: 129, key: A Minor",
  "|ggd'd'|e'/2f'/2g'/2e'/2d'2|c'c'bb|aage'|"
]</pre></code>

At run time, the hook will be adapted onto the chord progression and key of each musical section, and repeated as many times as will fit into that section. It is played by the “hook” instrument (see below), so if the hook (instrument) is one of the players in a given song segment, you will hear the hook (music).

The key specified in the first line is important because it tells the program how to adapt the notes onto parts that might be in a different key. (i.e. if you write a hook melody that’s in the key of A but tell the program it’s in the key of C...well, actually, that might be cool. You should try it and tell me what happens). As with musical elements, you can have more than one line of ABC notation if you want to have a harmonized or overlapping melody.

<h3>THE INSTRUMENTS</h3>

AutoHarp has seven instrument classes:
- drumLoop 
- bass 
- rhythm 
- pad 
- lead 
- hook 
- theme 

Each can be assigned one of 128 MIDI instrument patches save DrumLoop, which will always, like, be drums. Each instrument plays according to rules as befit its role in the band. The band is represented as a list in the JSON file:
<code><pre>"instruments" : [
 "uid: bass, instrumentClass: bass, patch: Electric Bass(finger)",
 "uid: drumLoop, instrumentClass: drumLoop, patch: Drum Loop", 
 "uid: hook, instrumentClass: hook, patch: Marimba", 
 "uid: pad, instrumentClass: pad, patch: Pad 8", 
 "uid: rhythm, instrumentClass: rhythm, patch: Electric Piano", 
 "uid: theme, instrumentClass: theme, patch: Electric Guitar(muted), themeIdentity: earworm", 
 "uid: theme2, instrumentClass: theme, patch: Kalimba, themeIdentity: slowTheme", 
 "uid: theme3, instrumentClass: theme, patch: Choir Aahs, themeIdentity: flowTheme"
 ],</pre></code>
You can add or remove instruments as you wish. Patch values can be broad (“piano” or “guitar” and AutoHarp will choose one that matches ) or specific (e.g. “Electric Piano 2”, “Electric Guitar (muted)”). The list of MIDI instrument names can be found here: [http://www.midi.org/techspecs/gm1sound.php](http://www.midi.org/techspecs/gm1sound.php). The Theme instrument has several subtypes (which control what kind of theme it plays). They are:
- ‘slowTheme’: plays in quarter or half notes 
- ‘fastTheme’: plays in eighth or sixteenth notes 
- ‘flowTheme’: plays a note along with each chord change 
- ‘cymbalTheme’: plays notes along with the most frequently occurring cymbal in the drum track 
- ‘melody’: plays the melody, whatever it is. 
- ‘earworm’: plays the same few notes, over and over 
- ‘harmonizer’: chooses another instrument and plays in harmony with it. 
  
<h3>THE SONG</h3>

The song is a list of the sections of the song, what kind of section it is, what instruments play, and what music it uses. Here’s a section of one (from full.json in the scaffolds directory):

<code><pre>...
{
 "firstHalfPlayers" : "bass, drumLoop, rhythm",
 "music" : "verse", 
 "secondHalfPlayers" : "bass, drumLoop, rhythm, hook",
 "tag" : "intro",
 "transition": "up"
},
...</pre></code>

AutoHarp will, whenever possible, split blocks of music into two halves and conduct each separately; sometimes instruments will start playing in the second half of the segment, as is seen above with the hook. The names here correlate to the “uid” values in the instrument list. The “music” corresponds to the key name of the music (verse, chorus, bridge), and the tag is what this section technically is. Transition is whether the song builds up, comes down, or stays where it is at the end of this section (valid transition values are “up”,”down”, and “straight”; “straight” is the default value).

  

- AutoHarp by default knows the following sections of a song, and knows more or less what they are: 
    - verse 
    - chorus 
    - bridge 
    - prechorus 
    - intro 
    - outro 
    - instrumental 
    - solo  
- However, you can call your music, or tag a section of song, anything you want. Once the song is constructed and instruments assigned, the “tag” value of the song section doesn’t matter at all. The only requirement is that the value of the “music” key matches an element in the music hash. So you could put in specific music for a prechorus, or an intro, or something called “Steve,” as long as you tell AutoHarp what “Steve” is (which you’d do in the “music” hash of the JSON file).  
- Similarly, the values for the “firstHalfPlayers” and “secondHalfPlayers” have to match the “uid” values in the instruments section of the file. And, similarly, you can name your bass, “Flea,” and your rhythm, “Cropper,” if you so desire, so long as you make clear to the program what those particular instruments are (in the instruments array of the JSON file). 
- As mentioned above, you can specify who plays, when they play, what the chords and melody are, what the structure of the song is, but you have no control over the actual notes. AHHAHAHA! NO CONTROL WHATSOEVER!!! 

<h3>QUESTIONS, COMMENTS, QUERIES, CRITICISMS, BUGS, AWESOME IDEAS:</h3>

Email [paul@piisoftware.com](mailto:paul@piisoftware.com), and put the word…

  

Q: No, hold the fuck on. I didn’t understand even one single thing I just read. 

A: Well, yeah. Look, I’m sorry. This is the alpha version of experimental software. I’m just one guy. I can only offer you the blue pill (or the red pill? Whichever one it was). The rest is up to you. Run the program and see what happens. That is the best I can give you. 

Q: But what if I have questions? 

A: Yeah...maybe if you emailed [paul@piisoftware.com](mailto:paul@piisoftware.com) and put the word “AutoHarp” in the subject line? 

Q: Whoa.

A: Yeah. 

Q: I KNOW KUNG-FU!

A: Not a question. But good for you.

Q: There is no spoon.

A: No there isn’t. Let’s wrap this up. If you’re submitting a bug, tell me the version number in this readme, what platform you’re on, and as much detail as you can give me. Are you interested in contributing on GitHub? Email me about that as well. And rock on.

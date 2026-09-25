# Shipping your Hardware Projects

Now that you have the design files, it's time to actually ship your hardware project and get it ready to submit!

The goal of shipping is to turn your project into a shareable piece that anyone can learn from, make, or otherwise find useful! It takes your project from just something local on your computer or in your room into something for the whole world to see.

_want to learn more about shipping? read more at the [codex](https://codex.hackclub.com/shipping). contains examples!_

## 1. Make sure you have all of your project files!

First off - check that all your project's files are actually in the repository! This includes a full CAD assembly in .STEP format, your PCB source files, and your firmware! This ensures that other people will actually be able to replicate your project!

It should look something like this:

![image](https://cdn.hackclub.com/019faa27-0dd7-78d7-ab11-79af1ad1b14e/paste-1785266113485.png)

_It's really hard to tell the difference between all the different files!_

## 2. Organize the different files!

Next, you should organize all your different files!

I recommend making 3 folders - one called "CAD", one called "PCB", and one called "firmware"

Drag and drop your files into their respective folders. Here's an example of what they should look like!

![image](https://cdn.hackclub.com/019faa2b-5bd4-7d82-a47d-3a43fd08760c/paste-1785266395604.png)
_same files, but organized this time around!_

## 3. Make a Bill Of Materials!

The next step is to make a bill of materials (BOM)!

A bill of materials is a list of all the parts & materials needed to make your project! You should include any components, modules, and any other parts you may need.

![image](https://cdn.hackclub.com/019faa3a-e3a5-7762-83fe-26dee71aaaea/paste-1785267413776.png)
You should store this in a **csv** (comma-separated value) format. It's plain text and works across almost every platform.

You can make your own, or use this template [here](https://docs.google.com/spreadsheets/d/1maI6o3gMH7iFf2YkcOIJNg3B32JRLoNRscTOKz6hCpg/edit?usp=sharing).

It may be tempting to skip this step, but it'll make it much easier to order your parts later!

## 4. Write a README.md about your project!

A README.md file is what ties your project together! It should include a short description of your project (what it does, how it works, why you made it), and also screenshots of your project!

Here's an example of what that looks like!

![image](https://cdn.hackclub.com/019faa3b-b681-71a1-845d-163630397f07/paste-1785267467646.png)

Make sure to include a screenshot of your PCB(s)/wiring diagram if applicable - it makes reviewing way easier for us and cuts down on time!

One snippet you can add to your project is this. It adds a PCB button to your README that opens your repository's PCB!

```
[![View PCB on KiCanvas](https://hack.club/pcb-badge)](https://kicanvas.org/?repo=https://github.com/<OWNER>/<REPOSITORY>/tree/main/pcb)
```

[![View PCB on KiCanvas](https://hack.club/pcb-badge)](https://kicanvas.org/?repo=https://github.com/hackclub/orpheus-pico)

## 5. Double check the requirements!

HOLD ON! Right before you actually submit, you should double check your project actually follows all the requirements! Make sure you tick off each of the following:

### Your project is actually complete:

- [x] It has a complete CAD assembly, with all components (including electronics)
- [x] You have firmware present, even if it's untested
- [x] You have asked for feedback from other people about your design

### Your GitHub repository contains all of your files:

- [x] a BOM, in CSV format in the root directory, WITH LINKS
- [x] the source files for your PCB, if you have one (.kicad_pro, .kicad_sch, gerbers.zip, etc)
- [x] A .STEP file of your project's 3D CAD model (and ideally the source design file format as well - .f3d, .FCStd, etc)
- [x] ANY other files that are part of your project (firmware, libraries, references, etc)

_if you're missing a .STEP file with all of your electronics and CAD, your project will not be approved_

### Your README.md is actually finished and has:

- [x] A short description of what your project is
- [x] A couple sentences on why you made the project

Pictures of your project:

- [x] A screenshot of a full 3D model with your project
- [x] A screenshot of your PCB, if you have one
- [x] A wiring diagram, if you're doing any wiring that isn't on a PCB
- [x] A BOM in table format at the end of the README

### And lastly, you do _not_ have:

- [ ] AI Generated READMEs
- [ ] Work that is not your own / copied from tutorials
- [ ] missing firmware/software

We know it's a lot! It's really important that you go through each item to maximize the chances of your project getting approved.

## 6. Submit!

Once you're done with your project, you're ready to submit it!

If you just finished a _design_ and are looking for funding, submit it for funding from your project page

![image](https://cdn.hackclub.com/019fb495-7a69-7fb6-aa42-80c52c50aef9/paste-1785441122200.png)
_you should get to this screen!_

If you just finished your build and are looking for Stardust, just ship your project and it'll get sent to the review queue!

![image](https://cdn.hackclub.com/019fb4a5-0c64-796c-b051-256f8078856c/paste-1785442142663.png)

You'll get a flat payout of 5 stardust per hour, with options to get more later!

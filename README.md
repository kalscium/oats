# oats
> short for onetime notes - a friction-less stack-based database for all your
> thoughts and notes that need only be written down once, so as to not forget.

***note:** it only runs on linux so far*

# Why Oats
---
Why should you choose to use oats instead of any one of the thousands of note
taking apps already available? In one simple word, **friction**. The other
available note taking apps have become so complex to the point of being a tool
that needs to be learnt to be used proficiently, and in the end, you spend more
time organising, than actual writing, and or note taking.

Oats on the other-hand, is designed to be bare-bones, for good reason, it does
not give you the choice even to have fancy colors or organisation but rather
removes any friction anything that would prevent you from just writing it down.
Oats removes the hesitation that you feel before writing, of do I really want
to spend my time doing this?

# Installation
---
## Compiling Locally
- Install a zig toolchain (obviously)
- Install git
- Clone the git repo
  ```sh
  git clone https://github.com/kalscium/oats.git
  ```
- Compile the project (optimization options are `Safe`, `Fast` & `Small`)
  ```sh
  zig build -DOptimize=ReleaseSafe
  ```
- The compiled binary should be in `zig-out/bin`
- Add the binary to your path and viola, it works.
## Downloading a Pre-Compiled Binary
- Open the releases tab on this github repo
- Find the latest release
- Download the corresponding binary for your system (`exe` for windows, `x86` or `arm`, etc)
- Add the binary to your path and viola, again, it just works.

# How does Oats work
---
Oats is a really simple stack-based thoughts/notes database, you push and pop
thoughts, and once they've been written, they're there forever
(unless you 'pop' it off the stack).
Each of the thoughts contains very little information, just the text itself, an
id (for syncing) and also a date.

## Constant time writes
Due to this simple design, Oats is able to be future-proof, efficient and easy
to sync. There's no need for worrying about if the database would get too large
or the application would get to slow, and due to the database design, writing
to the database will always be **O(1) constant time** so even if the database
was in the TiBs, writing would still be buttery smooth as if the database was
empty.

## Syncing
Syncing between two databases in oats is dead-simple due to it's `id` sytem,
each note/thought is allocated it's own id (usually based off of the time) that
it uses to organise the notes and also remove duplicates when importing another
database. Backups are also just as simple as syncing.

## Resistant to corruption
Due to the stack design of the Oats database, even if two operations on the
stack were to happen at the same time, in the worst case scenario, as the stack
pointer is updated last, after the data is written, the two operations might
be written out of order, in which you could just simply sort the database
`oats sort` and all would be well.

## Exporting to Markdown
Oats supports exporting to markdown, which converts all the thoughts and notes
into a pretty markdown format with the timestamps written whenever there's a
large gap in time (as either a heading (for different days) or a subheading
(for a different hour)).

## Tags
Most note taking apps have tags to organise things, so does oats, technically.
Tags aren't an 'officially' supported feature of oats, as mentioned above,
though you can implement a similar feature by simply including a unique tag
identifier at the end of your thoughts block, that you can later search for
using something like `CTRL+F`

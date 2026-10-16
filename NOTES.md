# Notes on recent xmonad.hs changes

## 1. Borders on lone windows

The goal: when a workspace has only one window, remove its border. When
a second window is added, restore borders. This should work per-screen,
independently of what other screens are doing.

### Why not use the built-in `lessBorders`/`smartBorders`?

XMonad.Layout.NoBorders provides layout modifiers for this, but they
have two problems in practice:

- `smartBorders` (which is `lessBorders Never`) only removes borders
  when there is a single screen total — useless in a multi-monitor
  setup.
- `lessBorders Screen` removes borders correctly per-screen, but the
  modifier tracks which windows currently have borders hidden in a
  piece of state called `currentHidden`. This state can drift out of
  sync with reality when workspaces are switched around, producing
  inconsistent behaviour that's hard to reproduce.

### The logHook approach

Instead of a layout modifier, the border management is done in a
`logHook`. XMonad runs the `logHook` after every state change (window
opened, closed, focused, workspace switched, etc.), making it a
reliable place to enforce invariants on the window set.

```haskell
loneWindowBorders :: X ()
loneWindowBorders = withDisplay $ \d -> do
    ws <- gets windowset
    bw <- asks (borderWidth . config)
    mapped' <- gets mapped
    changess <- mapM (\scr ->
        case W.stack (W.workspace scr) of
            Nothing -> return []
            Just stk -> do
                -- Count only windows that are actually shown: layouts
                -- like Full keep other windows in the stack but unmap them.
                let wins  = W.integrate stk
                    shown = filter (`S.member` mapped') wins
                    b     = if length shown == 1 then 0 else bw
                mapM (\w -> do
                    wa <- io $ getWindowAttributes d w
                    if fromIntegral (wa_border_width wa) /= b
                        then io (setWindowBorderWidth d w b) >> return True
                        else return False
                    ) wins
        ) (W.current ws : W.visible ws)
    if or (concat changess) then windows id else return ()
```

**`X ()`** is XMonad's main monad — a `StateT`/`ReaderT` stack that
carries the window set as mutable state, the display connection and
config as a read-only environment, and sits on top of `IO`. Most
XMonad actions return `X ()`.

**`withDisplay $ \d -> do ...`** unwraps the X11 `Display` connection
from the environment so you can call X11 library functions with it.

**`gets windowset`** reads the current window set from the XMonad state.
`gets f` is shorthand for `get >>= return . f`.

**`asks (borderWidth . config)`** reads the configured border width from
the environment. `asks f` is shorthand for `ask >>= return . f`.

**`W.current ws : W.visible ws`** builds a list of all screens that are
currently showing a workspace — `current` is the focused screen,
`visible` is every other screen.

**`W.stack (W.workspace scr)`** gets the window stack for the workspace
a given screen is showing. The result is `Maybe (W.Stack Window)`:
`Nothing` means the workspace is empty, `Just stk` means it has
windows. `W.Stack` has three fields: `focus` (the focused window),
`up` (windows above it in the stack), and `down` (windows below).

**`W.integrate stk`** flattens a `W.Stack` into a plain list:
`reverse up ++ [focus] ++ down`. This is where the name `wins` (a list
of all windows on the workspace) comes from.

**`gets mapped`** and **`filter (`S.member` mapped') wins`** — being
in the stack doesn't mean a window is on screen. Some layouts, `Full`
in particular, keep every window in the stack but only display the
focused one; xmonad hides (unmaps) the rest. XMonad's state keeps the
set of currently mapped windows in `mapped :: Data.Set Window`, so
`shown` is the subset of `wins` that is actually visible. It's
`shown`, not `wins`, that decides whether there's a lone window.

An earlier version used `length wins == 1`, which meant `Full` with two
or more windows on the workspace drew a border around the only visible
window.

`mapped` is up to date by the time the `logHook` runs: `windows`
reveals and hides windows (updating `mapped`) first, then calls the
`logHook` at the end.

The border width `b` is still applied to *every* window in `wins`,
hidden ones included. That way, when focus moves to another window in
`Full`, the window being revealed already has the right border and
nothing needs to be re-tiled.

Floating windows count as shown windows, so a floating window over a
`Full` window gives both of them borders.

**`mapM`** is the monadic version of `map` — it applies a function that
returns a monadic action to each element of a list, sequences those
actions, and collects the results into a list. Here it is used twice:
once over screens (producing `[[Bool]]`, hence `changess` — a list of
`changes`, one per screen), and once over windows within each screen
(producing `[Bool]`).

**`io`** lifts a plain `IO` action into the `X` monad. It is `liftIO`
under another name.

**`getWindowAttributes d w`** asks the X server for the current
attributes of window `w`, including its actual border width
(`wa_border_width`). This is important: XMonad's `tileWindow` reads
the *actual* border width from the X server when deciding how to
position a window, so we need to know what it currently is before
deciding whether to change it.

**`setWindowBorderWidth d w b`** calls through to `XSetWindowBorderWidth`
to update the border width attribute on window `w`.

**`>> return True`** sequences two actions: first set the border width,
then return `True` (meaning "something changed"). The `>>` operator
is like `;` in an imperative language — run the left side for its
effect, discard its result, then run the right side.

**`if or (concat changess) then windows id else return ()`** — after
processing all screens, `changess` is a `[[Bool]]`. `concat` flattens
it to `[Bool]`, and `or` checks whether any element is `True`. If
anything changed, `windows id` is called.

`windows id` applies the identity function to the window set — i.e. it
changes nothing, but it forces XMonad to re-run the layout and
re-tile all windows. This is necessary because `tileWindow` uses the
actual border width to compute window positions, so changing the
border width without re-tiling leaves a gap where the border used to
be. After `windows id` re-tiles, XMonad runs the `logHook` again; on
that second run, `getWindowAttributes` reports the correct border
width, nothing needs to change, `changess` is all `False`, and the
function returns without calling `windows id` again.

### Chaining in the logHook

```haskell
logHook = dynamicLogWithPP xmobarPP
              { ppOutput = hPutStrLn xmproc
              , ppTitle  = xmobarColor "green" ""
              } >> loneWindowBorders
```

`>>` sequences two `X ()` actions: run `dynamicLogWithPP ...` for its
effect (updating xmobar), discard its `()` result, then run
`loneWindowBorders`. The `$` that was here before was removed because
`>>` has higher precedence than `$`, so keeping `$` would have caused
the parser to try to sequence `xmobarPP { ... }` (a config value, not
an action) with `loneWindowBorders`, which is a type error.

The record update `xmobarPP { ppOutput = ..., ppTitle = ... }` works
without explicit parentheses because in Haskell's grammar, `{ ... }`
is a postfix operation on an atomic expression and binds to `xmobarPP`
directly, making `dynamicLogWithPP (xmobarPP { ... })` the natural
parse.

---

## 2. Per-workspace default layouts

```haskell
myLayoutHook = desktopLayoutModifiers $
        onWorkspace "4" presentationFirst $
        onWorkspace "9" fullFirst defaultLayouts

presentationFirst =
        named "Presentation" (Mirror (Tall 1 (3/100) (1/2))) |||
        named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
        ThreeColMid 1 (3/100) (1/2) |||
        Tall 1 (3/100) (1/2) |||
        Full

fullFirst =
        Full |||
        named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
        ThreeColMid 1 (3/100) (1/2) |||
        Tall 1 (3/100) (1/2) |||
        named "Presentation" (Mirror (Tall 1 (3/100) (1/2)))

defaultLayouts =
        named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
        ThreeColMid 1 (3/100) (1/2) |||
        Tall 1 (3/100) (1/2) |||
        named "Presentation" (Mirror (Tall 1 (3/100) (1/2))) |||
        Full
```

`onWorkspace` is from `XMonad.Layout.PerWorkspace`. Its signature is
roughly `onWorkspace :: WorkspaceId -> l1 a -> l2 a -> PerWorkspace l1 l2 a`:
use the first layout on the named workspace, and the second layout
everywhere else. The workspace IDs `"4"` and `"9"` are strings matching
the default workspace names (`map show [1..9]`).

To special-case more than one workspace, the calls are nested. The `$`
makes the whole `onWorkspace "9" fullFirst defaultLayouts` expression
the "everywhere else" argument of `onWorkspace "4" ...`, so the result
is:

- workspace 4 → `presentationFirst`
- workspace 9 → `fullFirst`
- every other workspace → `defaultLayouts`

Each further special case is another `onWorkspace "N" layout $` line
above the last one.

**`|||`** is the layout combinator. It creates a value of type
`Choose l1 l2 a` which starts with `l1` as the active layout and
cycles to `l2` (and further) when you press `Mod+Space`. There is no
separate list of layouts — `|||` is right-associative so
`l1 ||| l2 ||| l3` is `l1 ||| (l2 ||| l3)`, a nested tree of `Choose`
values.

The three chains contain the same five layouts in different orders, so
cycling with `Mod+Space` on workspace 4 or 9 still reaches every layout —
it just starts at Presentation or Full instead of Growing Grid.

A workspace that already exists keeps its current layout when the
config is reloaded with `Mod+q`; `Mod+Shift+Space` resets it to the
first layout in its chain.

---

## 3. Layout arguments

Tall, ThreeColMid and autoMaster share the same idea for their
arguments: a number of master windows and a resize step. They also
respond to the same messages: `Mod+h`/`Mod+l` send `Shrink`/`Expand`,
and `Mod+,`/`Mod+.` send `IncMasterN` to add or remove master windows.

### `Tall 1 (3/100) (1/2)`

| Arg      | Meaning                                                   |
|----------|-----------------------------------------------------------|
| `1`      | Number of master windows                                  |
| `3/100`  | Shrink/Expand step: 3% of the screen width per keypress   |
| `1/2`    | Initial width of the master pane: half the screen         |

One master column on the left, the remaining windows stacked on the
right. The "Presentation" layout, `Mirror (Tall 1 (3/100) (1/2))`, is
the same thing rotated 90°: the master is a full-width pane across the
top, and `1/2` is its share of the screen *height*.

### `ThreeColMid 1 (3/100) (1/2)`

Same three arguments as Tall: number of master windows, resize step,
and initial width of the master column. The master column is in the
middle, and the remaining windows alternate between the left and right
columns, which share the leftover width. (`ThreeCol`, without "Mid",
puts the master on the left with two stack columns to its right.)

### `autoMaster 1 (1/100) (Grid (16/9))`

| Arg            | Meaning                                                 |
|----------------|---------------------------------------------------------|
| `1`            | Number of master windows                                |
| `1/100`        | Shrink/Expand step: 1% of the screen height per keypress |
| `Grid (16/9)`  | The layout used for the non-master windows              |

`autoMaster` (from `XMonad.Layout.AutoMaster`) is a layout modifier. It
puts the master window(s) in a full-width row across the top and hands
the area below to the wrapped layout — here `Grid`.

Unlike Tall, the split isn't a fixed fraction. The master's height is
computed from the number of windows (`masterHeight` in
`AutoMaster.hs`):

| Windows | Master height             |
|---------|---------------------------|
| 1       | 100%                      |
| 2       | 80%                       |
| 3       | ~72%                      |
| …       | drops ~7.8% per window    |
| 8+      | 33%                       |

So the master shrinks to make room as windows are added — hence the
name "Growing Grid". If there are no more windows than the master count,
they simply share the screen side by side.

Shrink/Expand don't set the height directly; they adjust a "bias" added
to the computed height, clamped to ±40%. At `1/100` each keypress only
moves the split by 1%, much finer than the 3% used by the other layouts.

### `Grid (16/9)`

The config imports `XMonad.Layout.GridVariants`, whose `Grid`
constructor takes a `Rational`. (The plain `XMonad.Layout.Grid` module
is different: its `Grid` takes no argument, and the equivalent is
`GridRatio (16/9)`.)

The argument is the *desired aspect ratio of each cell*, as
width/height. It does not fix the number of rows or columns — those are
chosen from the window count and the available area so that cells come
out as close to 16:9 as possible (`arrangeAspectGrid` in
`GridVariants.hs`):

1. Compute the ideal fractional column count:
   `sqrt(screen_aspect × nwins / aspect)`.
2. Try that number rounded down and rounded up.
3. For each, work out the rows needed and the resulting cell shape;
   keep whichever is closer to the target aspect.
4. Spread windows as evenly as possible across columns, so some
   columns may have one more window than others.

Inside "Growing Grid", the grid only gets the area below the master,
and that area gets taller as windows are added, so the best column
count changes as the window count grows. A smaller ratio (e.g. `1`)
favours squarer cells; a larger one (e.g. `3`) favours wide, short
cells, so fewer columns with more rows stacked in each.

import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeysP)
import XMonad.Config.Desktop(desktopConfig, desktopLayoutModifiers)


import XMonad.Layout.AutoMaster
import XMonad.Layout.GridVariants
import XMonad.Layout.ThreeColumns
import XMonad.Layout.Renamed
import XMonad.Layout.NoBorders


import System.IO

main = do
        xmproc <- spawnPipe "xmobar"
        xmonad $ docks def
                { layoutHook = myLayoutHook
                , logHook    = dynamicLogWithPP  $  xmobarPP
                                { ppOutput       =  hPutStrLn xmproc
                                , ppTitle        =  xmobarColor "green" ""
                                }
                , modMask    = mod4Mask  -- Rebind Mod to the Windows key
                , terminal   = "terminator"
                }
                `additionalKeysP`
                [ ("M-S-l", spawn "xscreensaver-command -lock")
                , ("M-S-x", spawn "~/bin/autorandr --change")
                , ("M-S-i", spawn "~/bin/autorandr --load internal-only")
                , ("M-S-s", spawn "~/bin/autoscreengrab")
                , ("M-S-z", spawn "~/bin/grab-screen-to-clipboard")
                , ("<XF86AudioMute>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle")
                , ("<XF86AudioRaiseVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +3%")
                , ("<XF86AudioLowerVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -3%")
                , ("<XF86Sleep>", spawn "xscreensaver-command -lock")
                ]
          where
                myLayoutHook            = desktopLayoutModifiers $
                       named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
                       ThreeColMid 1 (3/100) (1/2) |||
                       Tall 1 (3/100) (1/2) |||
                       named "Presentation" (Mirror (Tall 1 (3/100) (1/2))) |||
                       noBorders Full
                       --layoutHook def
                       --
                       --
                       -- When bug-fixing becomes a thing:
                       --  add to myLayoutHook: "lessBorders OtherIndicated $" or "lessBorders Screen $"

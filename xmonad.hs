import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeysP)
import XMonad.Config.Desktop(desktopConfig, desktopLayoutModifiers)


import XMonad.Layout.AutoMaster
import XMonad.Layout.GridVariants
import XMonad.Layout.ThreeColumns
import XMonad.Layout.Named


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
                , ("M-S-x", spawn "/home/mike/bin/autorandr --change")
                , ("M-S-i", spawn "/home/mike/bin/autorandr --load internal-only")
                , ("M-S-s", spawn "/home/mike/bin/autoscreengrab")
                ]
          where
                myLayoutHook            = desktopLayoutModifiers $              --layout hooks: add a multicolumn layout to the default set
                       named "Slave Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
                       ThreeColMid 1 (3/100) (1/2) |||
                       layoutHook defaultConfig

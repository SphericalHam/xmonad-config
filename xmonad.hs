import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeys)
import XMonad.Config.Desktop(desktopConfig, desktopLayoutModifiers)


import XMonad.Layout.AutoMaster
import XMonad.Layout.Grid
import XMonad.Layout.ThreeColumns


import System.IO

main = do
        xmproc <- spawnPipe "xmobar"
        xmonad $ defaultConfig
                { manageHook = manageDocks      <+> manageHook defaultConfig
                , layoutHook = avoidStruts       $  myLayoutHook
                , logHook    = dynamicLogWithPP  $  xmobarPP
                                { ppOutput       =  hPutStrLn xmproc
                                , ppTitle        =  xmobarColor "green" ""
                                }
                , modMask    = mod4Mask  -- Rebind Mod to the Windows key
                }
          where
                myLayoutHook            = desktopLayoutModifiers $              --layout hooks: add a multicolumn layout to the default set
                       autoMaster 1 (1/100) Grid ||| 
                       ThreeCol 1 (3/100) (1/2) ||| 
                       ThreeColMid 1 (3/100) (1/2) |||
                       layoutHook defaultConfig

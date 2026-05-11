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
import XMonad.Layout.PerWorkspace (onWorkspace)
import qualified XMonad.StackSet as W


import System.IO

loneWindowBorders :: X ()
loneWindowBorders = withDisplay $ \d -> do
    ws <- gets windowset
    bw <- asks (borderWidth . config)
    changess <- mapM (\scr ->
        case W.stack (W.workspace scr) of
            Nothing -> return []
            Just stk -> do
                let wins = W.integrate stk
                    b    = if length wins == 1 then 0 else bw
                mapM (\w -> do
                    wa <- io $ getWindowAttributes d w
                    if fromIntegral (wa_border_width wa) /= b
                        then io (setWindowBorderWidth d w b) >> return True
                        else return False
                    ) wins
        ) (W.current ws : W.visible ws)
    if or (concat changess) then windows id else return ()

main = do
        xmproc <- spawnPipe "xmobar"
        xmonad $ docks def
                { layoutHook = myLayoutHook
                , logHook    = dynamicLogWithPP xmobarPP
                                { ppOutput       =  hPutStrLn xmproc
                                , ppTitle        =  xmobarColor "green" ""
                                } >> loneWindowBorders
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
                myLayoutHook = desktopLayoutModifiers $
                        onWorkspace "4" presentationFirst defaultLayouts
                presentationFirst =
                        named "Presentation" (Mirror (Tall 1 (3/100) (1/2))) |||
                        named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
                        ThreeColMid 1 (3/100) (1/2) |||
                        Tall 1 (3/100) (1/2) |||
                        Full
                defaultLayouts =
                        named "Growing Grid" (autoMaster 1 (1/100) (Grid (16/9))) |||
                        ThreeColMid 1 (3/100) (1/2) |||
                        Tall 1 (3/100) (1/2) |||
                        named "Presentation" (Mirror (Tall 1 (3/100) (1/2))) |||
                        Full

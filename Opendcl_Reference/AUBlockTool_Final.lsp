
(defun C:AUBT ( / )
  (command "OPENDCL")
  (dcl_Project_Load "AUBlockTool")
  (dcl_Form_Show AUBlockTool_PalBlkTool)
  (princ)
)

;; Gets fired before the form is shown.
(defun c:AUBlockTool_PalBlkTool_OnInitialize ( /)
  (dcl_ListBox_Clear AUBlockTool_PalBlkTool_BlockNameList)
  (dcl_LISTBOX_ADDLIST AUBlockTool_PalBlkTool_BlockNameList (GetBlockNames))
)

;; Preview the block.
(defun c:AUBlockTool_PalBlkTool_BlockNameList_OnSelChanged (nSelection sSelText /)
    (dcl_BlockView_DisplayBlock AUBlockTool_PalBlkTool_BlockView sSelText)
)

;; Selection Set Pick button was clicked.
(defun c:AUBlockTool_PalBlkTool_cmdSSPick_OnClicked (/)
  (setq *blocks* (ssget '((0 . "INSERT"))))
  (UpdateSStext)
)


;; Multi Insert button was clicked.
;; Get the current values of the controls.
;; Insert the block multiple times.
(defun c:AUBlockTool_PalBlkTool_cmdMInsBlk_OnClicked ( / CSel BlkName X Y Z rot pt)
   (setq CSel (dcl_ListBox_GetCurSel AUBlockTool_PalBlkTool_BlockNameList))
   (setq BlkName (dcl_ListBox_GetText AUBlockTool_PalBlkTool_BlockNameList CSel))
   (setq X (dcl_Control_GetValue AUBlockTool_PalBlkTool_SliderBarXScale))
   (setq Y (dcl_Control_GetValue AUBlockTool_PalBlkTool_SliderBarYScale))
   (setq Z (dcl_Control_GetValue AUBlockTool_PalBlkTool_SliderBarZScale))
   (setq rot (dcl_Control_GetValue AUBlockTool_PalBlkTool_AngleSliderBlkRot))

   (setq *blocks* (ssadd))
   (while (setq pt (getpoint "Select base point\\Right-click to exit: "))
     (command ".insert" BlkName "X" X "Y" Y "Z" Z "R" rot pt)
     (ssadd (entlast) *blocks*)
     (UpdateSStext)
   )
   (princ)
)

;; X SliderBar Scrolling.
(defun c:AUBlockTool_PalBlkTool_SliderBarXScale_OnScroll (nValue /)
   (dcl_Control_SetText AUBlockTool_PalBlkTool_txtScaleX (itoa nValue))
   (DoScale 41 nValue)
   (UpdateLinks (itoa nValue))
   (princ)
)

;; Y SliderBar Scrolling.
(defun c:AUBlockTool_PalBlkTool_SliderBarYScale_OnScroll (nValue /)
   (dcl_Control_SetText AUBlockTool_PalBlkTool_txtScaleY (itoa nValue))
   (DoScale 42 nValue)
   (princ)
)

;; Z SliderBar Scrolling.
(defun c:AUBlockTool_PalBlkTool_SliderBarZScale_OnScroll (nValue /)
   (dcl_Control_SetText AUBlockTool_PalBlkTool_txtScaleZ (itoa nValue))
   (DoScale 43 nValue)
   (princ)
)


;; Link Pic. Box was clicked
;; Update controls based on it's current picture.
(defun c:AUBlockTool_PalBlkTool_PicBoxScaleLink_OnClicked ( / Pic)
  (setq Pic (dcl_Control_GetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink))
  (cond
    ((= Pic 100);_ not linked
      (dcl_Control_SetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink 101)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarYScale nil)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleY nil)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarZScale T)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleZ T)
    )
    ((= Pic 101);_ XY linked
      (dcl_Control_SetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink 102)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarYScale nil)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleY nil)     
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarZScale nil)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleZ nil)     
    )
    ((= Pic 102);_ XYZ linked
      (dcl_Control_SetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink 100)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarYScale T)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleY T)     
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_SliderBarZScale T)
      (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtScaleZ T)     
    )
  );_ cond
 (princ)
)

;; Randomize CheckBox was clicked.
(defun c:AUBlockTool_PalBlkTool_chkScaleRand_OnClicked (nValue /)
  (if (= nValue 0)
    (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtRandomAmount nil)
    (dcl_Control_SetEnabled AUBlockTool_PalBlkTool_txtRandomAmount T)
  )
)

;; Rotation Angle Slider Scrolling.
;; Rotate the blocks in the selection set.
(defun c:AUBlockTool_PalBlkTool_AngleSliderBlkRot_OnScroll (nValue / cnt ed)
   (setq cnt 0)
   (if *blocks*
     (progn   
       (while (< cnt (sslength *blocks*))
         (setq ed (entget (ssname *blocks* cnt)))
         (entmod (subst (cons 50 (dtor nValue)) (assoc 50 ed) ed))
         (setq cnt (1+ cnt))
       );_ while
     );_ progn
     (princ "\nNothing in the selection set.")
   );_ if
   (princ)
)




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;*********************************  UTILITY FUNCTIONS  *********************************************
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; Check if controls are linked
;; & scale blocks in other direction(s) if so.
(defun UpdateLinks (sText / nValue)
   (setq nValue (atoi sText))
   (if (> (dcl_Control_GetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink) 100);_ if XY linked
     (progn
       (dcl_Control_SetValue AUBlockTool_PalBlkTool_SliderBarYScale nValue)
       (dcl_Control_SetText AUBlockTool_PalBlkTool_txtScaleY sText)     
       (DoScale 42 nValue)
     )
   )

   (if (= (dcl_Control_GetPicture AUBlockTool_PalBlkTool_PicBoxScaleLink) 102);_ if XYZ linked
     (progn
       (dcl_Control_SetValue AUBlockTool_PalBlkTool_SliderBarZScale nValue)
       (dcl_Control_SetText AUBlockTool_PalBlkTool_txtScaleZ sText)
       (DoScale 43 nValue)
     )
   )  
)

;; Update Selection Set Label.
(defun UpdateSStext ( / )
  (if *blocks*
    (dcl_Control_SetCaption AUBlockTool_PalBlkTool_lblSSet (strcat (itoa (sslength *blocks*)) " objects in Selection Set"))
    (dcl_Control_SetCaption AUBlockTool_PalBlkTool_lblSSet "0 objects in Selection Set")
  ) 

)

;; Scale the blocks in the *blocks* Selection Set in the given direction.
;; Dir: 41=X, 42=Y, 43=Z
(defun DoScale (Dir NewScale / cnt ed fuzz MinScale)
   (setq cnt 0)
   (setq fuzz (atof (dcl_Control_GetText AUBlockTool_PalBlkTool_txtRandomAmount)))
   (setq MinScale (- NewScale fuzz))
   (if (< MinScale 0.0)
     (setq MinScale 1.0)
   )

   (if *blocks*
     (progn 
       (while (< cnt (sslength *blocks*))
         (if (/= (dcl_Control_GetValue AUBlockTool_PalBlkTool_chkScaleRand) 0)
           (setq NewScale (getrandnum MinScale (+ NewScale fuzz)))
         )
         (setq ed (entget (ssname *blocks* cnt)))
         (entmod (subst (cons Dir NewScale) (assoc Dir ed) ed))
         (setq cnt (1+ cnt))
       );_ while
     );_ progn
     (princ "\nNothing in the selection set.")
   );_ if
)

;; Getrandnum returns a real number between minNum and maxNum.
;; By: Stig Madsen
(DEFUN getrandnum (minNum maxNum / randnum)
    (DEFUN randnum (/ modulus multiplier increment random)
        ;; Randnum.lsp
        ;; Returns a random number.
        ;; Written by Paul Furman, 1996.
        ;; Based on algorithm by Doug Cooper, 1982.
        (IF (NOT seed)
            (SETQ seed (GETVAR "DATE"))
        )
        (SETQ modulus    65536
              multiplier 25173
              increment  13849
              seed       (REM (+ (* multiplier seed) increment) modulus)
              random     (/ seed modulus)
        )
    )
    (IF (NOT (< minNum maxNum))
        (PROGN (SETQ tmp    minNum
                     minNum maxNum
                     maxNum tmp
               )
        )
    )
    (SETQ random (+ (* (randnum) (- maxNum minNum)) minNum))
)


;;degreed to radian
(defun dtor (x)
  (* (/ x 180.0) pi)
)



;; this function retrieves all the block names in the DWG.
(DEFUN GetBlockNames (/ BlockInfo BlkLst Blk)
    (SETQ BlockInfo (TBLNEXT "BLOCK" T))
    ;; get the first block in the block table record
    ;; loop through all block records, get block name
    ;; ignore anonymous blocks, dim's, xref's, etc...
    ;; add the block name to the list 'BlkLst
    ;; goto next block
    (WHILE BlockInfo
        (SETQ blk (CDR (ASSOC 2 BlockInfo)))
        (IF (NOT (WCMATCH blk "`*U*,`*D*,`*X*,`*T*,_*,*|*,A$*"))
            (SETQ BlkLst (APPEND BlkLst (LIST blk)))
        )
        (SETQ BlockInfo (TBLNEXT "BLOCK"))
    )
    BlkLst
)

(princ "\nType AUBT to run the command")
(princ)

;|«Visual LISP© Format Options»
(80 2 50 2 nil "end of " 80 50 2 0 2 nil nil nil T)
;*** DO NOT add text below the comment! ***|;

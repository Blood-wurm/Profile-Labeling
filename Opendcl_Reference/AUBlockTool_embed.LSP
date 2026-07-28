
(defun C:AUBT2 ( / )
  (command "OPENDCL")

(setq project
'("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")
)
  
  (dcl_project_import project nil nil)
  ;(dcl_Project_Load "AUBlockTool" T)
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

(princ "\nType AUBT2 to run the command")
(princ)

;|«Visual LISP© Format Options»
(80 2 50 2 nil "end of " 80 50 2 0 2 nil nil nil T)
;*** DO NOT add text below the comment! ***|;

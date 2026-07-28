



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

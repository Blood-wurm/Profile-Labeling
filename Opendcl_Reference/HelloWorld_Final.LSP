
; the following command will ensure the 
; appropriate OpenDCL ARX file is loaded.
(command "_OPENDCL")

(defun c:Hello ()
   ; call the method to load the HelloWorld.odcl file.
   (dcl_Project_Load "HelloWorld" T)
   ; call the method to show the Hello World dialog box example.
   (dcl_Form_Show HelloWorld_Form1)
   (princ)
)

; This fires just before the form is shown.
(defun c:HelloWorld_Form1_OnInitialize (/)
   (dcl_Control_SetCaption HelloWorld_Form1_Label1 "Type Something:") ; Change the labels Caption.
)

; This gets called when the OK button is clicked
(defun c:HelloWorld_Form1_TextButton1_OnClicked (/)
   (setq sText (dcl_Control_GetText HelloWorld_Form1_TextBox1)) ; Get the Text property from the Text Box.
   (dcl_messagebox (strcat "You typed: " sText)) ; Show a MessageBox with the user entered text.
   (dcl_Form_Close HelloWorld_Form1) ; Close the form.
   (princ)
)



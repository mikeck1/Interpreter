        include Win64API.inc

        .DATA

;---------------------
; EQUATES 
;---------------------

MAX_RAM             EQU     1024                            ;Maximum size of emulated CPU's RAM
INVALID_HANDLE      EQU     -1                              ;CreateFile returns this value if it failed
_CR                 EQU     0Dh                             ;Carriage return character
_LF                 EQU     0Ah                             ;Line Feed (new line) character
NULL_PTR            EQU     0
ERROR               EQU     1                               ;return code indicating an error occurred
READ_FILE_ERROR     EQU     0                               ;ReadFile will return 0 if an error occurred

_LOAD			    EQU     05h								; Various
_XOR			    EQU     44h								; labels for the 8 bit 
_ADD                EQU     11h								; operations used in the
_STORE              EQU     06h								; emulator
_LOADR              EQU     55h
_STORER             EQU     66h
_OUT                EQU     0CCh
_SUB                EQU     22h
_JNZ                EQU     0AAh
_HALT               EQU     0FFh

;---------------------
;variables
;---------------------
; Variables for the backend Virtual Machine.
errMsgFileOpen      byte    "ERROR:  Unable to open input file", _CR, _LF
errNoOpcodeMatch    byte    "ERROR:  Cannot find matching Op code", _CR, _LF
filename            byte    "machine.bin", NULL            ;file name must be null terminated
programBuffer       byte    MAX_RAM dup (0)                 ;max size of RAM 1K
returnCode          dword   0                               ;used to return program status back to OS
bytesWritten        dword   0
BytesRead           dword   0                               ;number of bytes read from file will be stored here
fileHandle          qword   0                               ;handle to file containing program
fileSize            dword   0                               ;size of file
hStdOut             qword   0                               ;handle to the standard output
hStdIn              qword   0                               ;handle to the standard input

; Interpreter Variables
Registers           byte    6 dup (?)	                    ; 8 bit Registers
_charOutput         byte    ?								; Holds output char from file


                    .CODE

Main                Proc

                    sub     rsp,40                          ;shadow memory and align stack
                                                            ;32 bytes for shadow memory
                                                            ;8 bytes to align stack

                    ;*********************************
                    ; Get Handle to Standard output
                    ;*********************************
                    mov     ecx,STD_OUTPUT_HANDLE           ;pass handle to get in ecx
                    call    GetStdHandle                    ;call Windows API
                    mov     hStdOut,rax                     ;save returned handle

                    ;*********************************
                    ; Get Handle to Standard input
                    ;*********************************
                    mov     ecx,STD_INPUT_HANDLE            ;pass handle to get in ecx
                    call    GetStdHandle                    ;call Windows API
                    mov     hStdIn,rax                      ;save returned handle

                    ;*********************************
                    ; Open existing file for Reading
                    ;*********************************
                    mov     rcx,offset fileName             ;name of file to open
                    mov     rdx,GENERIC_READ                ;
                    mov     r8,FILE_SHARE_NONE              ;file sharing - NONE
                    mov     r9,NULL_PTR                     ;
                    mov     qword ptr [rsp+32],OPEN_EXISTING            ;file must exist
                    mov     qword ptr [rsp+40],FILE_ATTRIBUTE_NORMAL    ;file attribute - normal
                    mov     qword ptr [rsp+48],NULL_PTR                 ;
                    call    CreateFileA
                    cmp     eax,INVALID_HANDLE              ;was open successful?
                    je      OpenError                       ;No....Display error and Exit
                    mov     fileHandle,rax                  ;Yes...then save file handle

                    ;********************************************
                    ; Determine the size of the file (in bytes)
                    ;********************************************
                    mov     rcx,fileHandle                  ;handle of open file
                    mov     rdx,NULL_PTR                    ;
                    call    GetFileSize                     ;Windows API function - returns file size
                    mov     fileSize, eax

                    ;********************************************
                    ; Make sure the size of the file doesn't 
                    ; exceed our buffer size. If it does then exit
                    ;********************************************
                    cmp     fileSize,LENGTHOF programBuffer ;Is file size greater than our buffer?
                    jc      ReadFromFile                    ;no...then read the entire file into our buffer
                    mov     returnCode,ERROR                ;yes..set return code to error
                    jmp     CloseFile                       ;     and exit

                    ;****************************************
                    ; Read the entire file into emulator RAM
                    ;****************************************
ReadFromFile:
                    mov     rcx,fileHandle                  ;handle to the file to read
                    mov     rdx,offset programBuffer        ;where to put data read
                    mov     r8d,fileSize                    ;number of bytes to read
                    mov     r9,offset bytesRead             ;returns bytes read in this variable
                    xor     rax,rax                         ;last parameter is 0
                    mov     [rsp+32],rax                    ;parameters > 4 are passed on the stack
                    call    ReadFile                        ;read the entire file into programBuffer
                    cmp     eax,READ_FILE_ERROR             ;was read successful?
                    jne     RunProgram                      ;Yes..then execute the program
                    mov     returnCode,ERROR                ;no...set return code to error
                                                            ;     and close file and exit
                    ;*********************************
                    ; Close the file
                    ;*********************************
CloseFile:
                    mov     rcx,fileHandle                  ;pass in handle to the file to close
                    call    CloseHandle
                    jmp     Finish

OpenError:
                    ;Let user know there was an error opening the file
                    mov     rcx,hStdOut                     ;1st parameter - handle of where to send message
                    mov     rdx,OFFSET errMsgFileOpen       ;2nd parameter - message to display
                    mov     r8,LENGTHOF errMsgFileOpen      ;3rd parameter - number of characters to display
                    mov     r9,OFFSET bytesWritten          ;4th parameter - pointer where bytes written will be stored
                    xor     rax,rax                         ;last parameter is 0
                    mov     [rsp+32],rax                    ;parameters > 4 are passed on the stack
                    call    WriteConsoleA                   ;display the error message
                    mov     returnCode,ERROR                ;let caller know there was an error
                    jmp     finish                          ;exit program
;WRITE T
RunProgram:
                    mov     r13, offset ProgramBuffer       ; r13 will act as an instruction pointer
					mov     r15, offset ProgramBuffer       ; to keep consistant address for data
                    mov     rbp, offset Registers           ; rbp is used for emulated registers
                    
ParseHex:
				    xor     r9, r9                          ; clear upper reg so can offset registers
                    xor     r12, r12                        ; clear upper reg for address
					xor		rcx, rcx						; In fOut, writeConsoleA gets these dirty

                    mov     r9b, [r13]                      ; Read current bit from the intruction
															; pointer.
															; Check linearly for next Operational function

                    cmp     r9b, _STORE                     ; Check if STORE
                    je      _fSTORE                        

                    cmp     r9b, _STORER                    ; Check if STORER
                    je      _fSTORER                       

                    cmp     r9b, _OUT                       ; Check if OUT
                    je      _fOUT                           

				    cmp     r9b, _LOAD                      ; Check if LOAD
                    je      _fLOAD                         

                    cmp     r9b, _LOADR                     ; Check if LOADR
                    je      _fLOADR                        

                    cmp     r9b, _XOR                       ; Check if XOR
                    je      _fXOR                         

                    cmp     r9b, _ADD                       ; Check if ADD
                    je      _fADD                          

                    cmp     r9b, _SUB                       ; Check if SUB
                    je      _fSUB                          

                    cmp     r9b, _JNZ                       ; Check if JNZ
                    je      _fJNZ                           

                    cmp     r9b, _HALT                      ; Check if HALT
                    je      _fHALT                          

                    jmp     _Error							; Cannot find  matching Op Code

_fLOAD:

                    inc     r13                             ; inc to reg
                    mov     r9b, [r13]                      ; Grab the reg
                    inc     r13                             ; go to address
                    mov     cx, [r13]                       ; Grab address
                    xchg    ch, cl                          ; Swap to big endian
                    mov     r12b, [r15 + rcx]               ; Grab address
                    mov     [rbp + r9], r12b                ; put value grabbed into the register 
                    inc     r13		                        ; inc to next op code
					inc		r13

                    jmp     ParseHex                        ; check next hexop



_fXOR:

                    inc     r13                             ; inc to the reg
                    mov     r9b, [r13]                      ; Read the reg
                    inc     r13                             ; go to reg 2
                    mov     r12b, [r13]                     ; grab reg 2
                    mov     al, [rbp + r12]                 ; grab value in reg 2
                    xor     [rbp + r9], al                  ; xor reg1 reg2
                    inc     r13                            

                    jmp     ParseHex					    ; check next hexop 



_fADD:

                    inc     r13                             ; inc to the reg
                    mov     r9b, [r13]                      ; Grab the reg
                    inc     r13                             ; inc reg 2
                    mov     r12b, [r13]                     ; Grab reg 2
                    mov     al, [rbp + r12]                 ; Grab value from reg 2
                    add     [rbp + r9], al                  ; Put into reg1
                    inc     r13                             

                    jmp     ParseHex                        ; check next hexop

_fSUB:

                    inc     r13                             ; Inc to the reg
                    mov     r9b, [r13]                      ; Grab the reg
                    inc     r13                             ; inc to reg 2
                    mov     r12b, [r13]                     ; Grab reg 2
                    mov     al, [rbp + r12]                 ; Grab value from reg 2
                    sub     [rbp + r9], al                  ; Sub value 2 from value in reg 1
                    inc     r13                             

                    jmp     ParseHex                        ; check next hexop

_fLOADR:

                    inc     r13                             ; Inc to the reg
                    mov     r9b, [r13]                      ; Read the reg
					mov     r12b, [rbp + r9]                ; Read the register value
                    inc     r13                             ; go to address
                    mov     cx, [r13]                       ; Read address
                    xchg    ch, cl                          ; Swap to big endian

                    mov     rdx, r15                        ; go to start of programBuffer and
                    add     rdx, rcx                        ; Add address
                    add     rdx, r12                        ; Add value in reg
                    mov     r12b, [rdx]                     ; Grab value in address + register

                    mov     [rbp + r9], r12b                ; put value grabbed into proper register
                    inc     r13
					inc		r13

                    jmp     ParseHex                        ; check next hexop

_fSTORE:

                    inc     r13                             ; Inc to address
                    mov     cx, [r13]                       ; Grab address
                    xchg    ch, cl                          ; Swap to big endian
                    mov     r9b, Registers                  ; Grab value from reg
                    mov     [r15 + rcx], r9b                ; Put value in program buffer
                    inc     r13		                        ; inc to address
					inc		r13								; Go to new instruction

                    jmp     ParseHex                        ; check next hexop

_fSTORER:

                    inc     r13                             ; Inc to the reg
                    mov     r9b, [r13]                      ; Grab the reg
                    inc     r13                             ; Point to the address operand
                    mov     cx, [r13]                       ; Grab address
                    xchg    ch, cl                          ; Swap to big endian
                    mov     rbx, r15                        ; Get address 0 of the program
                    add     rbx, rcx                        ; go to address
                    mov     r12b, [rbp + r9]                ; grab register code
                    add     rbx, r12                        ; go to the placement in the register array
                    mov     r9b, Registers                  ; grab register 0
                    mov     [rbx], r9b                      ; put value into address + register
                    inc     r13		                        ; inc to address
					inc		r13

                    jmp     ParseHex						; check next hexop

_fOUT:

                    inc     r13                             ; inc to the reg
                    mov     r9b, [r13]                      ; Read the register
                    mov     r12b, [rbp + r9]                ; grab value from regiser
                    mov     _charOutput, r12b               ; move value from register into _charOutput
                    xor	    rax, rax                        ; last parameter is 0
                    mov     [rsp+32], rax                   ; parameters > 4 are passed on the stack
					mov     rcx,hStdOut                     ; 1st parameter - handle of where to send message
                    mov     r9, OFFSET bytesWritten		    ; 2nd parameter - message to display
                    mov     r8d, SIZEOF _charOutput         ; 3rd parameter - number of characters to display
                    mov     rdx, OFFSET _charOutput         ; 4th parameter - pointer where bytes written will be store
                    
					call    WriteConsoleA					; display the error message
                    inc     r13                             ; Point to the next instruction

                    jmp     ParseHex                        ; check next hexop                           

_fJNZ:

                    inc     r13                             ; Inc to the reg
                    mov     r9b, [r13]                      ; Read the register
                    mov     r9b, [rbp + r9]                 ; Get value from regiser
                    cmp     r9b, 0                          ; Check if value is zero
                    je      _ifzero                         ; if the value iz zero                             
                    inc     r13          
                    mov     cx, [r13]                       ; Grab address
                    xchg    ch, cl                          ; Swap to big endian

                    mov     r9, r15                         ; Beginning of program buffer
                    add     r9, rcx                         ; and the address
                    mov     r13, r9                         ; move instruction pointer to address
 
                    jmp     ParseHex                        ; check next hexop

        _ifzero:

                    inc     r13                             
					inc     r13
					inc     r13

                    jmp     ParseHex                        ; check next hexop


_fHALT:

                    jmp     Finish							; End of program

_error:
					mov     rcx,hStdOut                     ; 1st parameter - handle of where to send message
                    mov     rdx,OFFSET errNoOpcodeMatch     ; 2nd parameter - message to display
                    mov     r8,LENGTHOF errNoOpcodeMatch    ; 3rd parameter - number of characters to display
                    mov     r9,OFFSET bytesWritten          ; 4th parameter - pointer where bytes written will be stored
                    xor     rax,rax                         ; last parameter is 0
                    mov     [rsp+32],rax                    ; parameters > 4 are passed on the stack
                    call    WriteConsoleA                   ; display the error message
                    mov     returnCode,ERROR                ; let caller know there was an error
                    jmp     Finish							; End of program

Finish:

														    ; End Program

                    mov     ecx,returnCode                  ;parameter 1 contains the return code
                    call    ExitProcess                     ;Windows API - terminates the program



Main                endp

                    END


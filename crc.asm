;------------------------------------------------------------------------------;
; Program znajdujący cykliczny kod nadmiarowy CRC                              ;
; Autor: Wiktor Kotala                                                         ;
;------------------------------------------------------------------------------;
global _start

SYS_READ  equ 0
SYS_WRITE equ 1
SYS_OPEN  equ 2
SYS_CLOSE equ 3
SYS_LSEEK equ 8
SYS_EXIT  equ 60

EXIT_SUCCESS equ 0
EXIT_FAILURE equ 1
SEEK_CUR     equ 1
STDOUT       equ 1

SIZEOF_DATA_LEN equ 2
SIZEOF_OFFSET   equ 4
MAX_POLY_LEN    equ 64

ASCII_0       equ 48
ASCII_1       equ 49
ASCII_NEWLINE equ 10

; Stałe trzymane w rejstrze r10b.
READ_DATA_LEN equ -1
READ_DATA     equ 0

section .bss
; Rozmiar bufora ustawiam na 2^16 + 4 bajtów, ponieważ:
; - dane będę wczytywał fragmentami, gdyż są one porozrzucane po pliku,
; - niewielka maksymalna długość fragmentu (2^16 bajtów) prawie zawsze pozwala
;   wczytać go w całości, co będę próbował zrobić,
; - dodatkowe 4 bajty są na przesunięcie, które wczytam razem z fragmentem.
data:     resb 65540 ; bufor do operacji wejścia / wyjścia
data_len: resw 1     ; długość fragmentu
crc_byte: resq 256   ; lookup table trzymające reszty z dzielenia wszystkich
                     ; możliwych bajtów przez wielomian CRC

section .text
; Przeznaczenie rejestrów:
; rbx - początkowo pierwszy argument (wielomian jako napis),
;       później reszta z dzielenia (czyli docelowo kod nadmiarowy CRC)
; r8  - wielomian CRC
; r9  - stopień wielomianu CRC
; r10 - trzyma informację, gdzie wrócić po zakończonym czytaniu (stałą READ_xxx)
; r12 - długość danych we fragmencie (data_len)
; r13 - przesunięcie (offset)
; rdi - argument funkcji systemowych, przez większość czasu trzyma deskryptor
;       pliku, z którego czytamy
; rax, rcx, rdx, rsi, r11 - rejestry na krótko żywotne zmienne pomocnicze

_start:
    ; Sprawdzam, czy podano poprawną liczbę argumentów.
    cmp dword [rsp], 3
    jne exit_with_error

    ; Obliczam wielomian CRC i jego stopień na podstawie argumentu programu.
    mov rbx, [rsp + 24] ; wielomian CRC jako napis (drugi argument)
    xor r8, r8          ; wielomian CRC jako 64-bitowa liczba
    xor r9, r9          ; licznik pętli, a po jej zakończeniu stopień wielomianu

poly_loop:
    mov al, [rbx + r9]  ; al = wielomian[r9]
    test al, al
    jz end_poly_loop    ; jeśli al == '\0', to wychodzimy z pętli
    cmp r9, MAX_POLY_LEN
    jae incorrect_poly  ; kontrolujemy długość wielomianu

    ; if (al == '0')
    cmp al, ASCII_0
    je char_is_zero
    ; else if (al == '1')
    cmp al, ASCII_1
    je char_is_one
    ; else

incorrect_poly:
    jmp exit_with_error

char_is_zero:
    shl r8, 1
    jmp next_char

char_is_one:
    shl r8, 1
    or r8, 1            ; ustawiam najmłodszy bit wielomianu na 1

next_char:
    inc r9
    jmp poly_loop

end_poly_loop:
    test r9, r9
    jz incorrect_poly   ; wielomian o stopniu zero uznajemy za błędny
    ; Przesuwam wielomian na najbardziej znaczące bity r8.
    mov rcx, MAX_POLY_LEN
    sub rcx, r9
    shl r8, cl

    ; if (open(file_path, O_RDONLY) < 0) exit(1);
    mov rax, SYS_OPEN
    mov rdi, [rsp + 16] ; ścieżka pliku wejściowego (pierwszy argument)
    xor rsi, rsi        ; flaga O_RDONLY
    syscall
    test rax, rax
    js exit_with_error
    mov rdi, rax        ; rdi = fd (deskryptor pliku)
    ; Uwaga! Wartość rejestru rdi pozostaje niezmieniona aż do zamknięcia pliku.
    
    ; Tworzę lookup table: xoruję wielomian CRC z każdym możliwym bajtem i
    ; zapisuję wyniki w tablicy crc_byte, aby później móc się do nich odwoływać.
    ; rdx - licznik bajtów (pętli zewnętrznej)
    ; rcx - licznik bitów (pętli wewnętrznej)
    ; rax - reszta po xorowaniu bajtu (dl << 56) z wielomianem (r8)
    ; rsi - adres tablicy crc_byte

    ; for (dl = 0; dl < 256; dl++)
    lea rsi, [rel crc_byte]
    xor rdx, rdx

lookup_loop:
    mov al, dl
    shl rax, 56 ; 8 najbardziej znaczących bitów rax ustawiam na dany bajt

    ; for (cl = 8; cl > 0; cl--)
    mov cl, 9
bit_loop:
    dec cl
    test cl, cl
    jz next_byte

    ; Jeżeli najbardziej znaczący bit jest ustawiony, to xoruję z wielomianem.
    ; W każdym przypadku zapominam o najbardziej znaczącm bicie, którego wartość
    ; to 0, bo jeśli wynosiła 1, to xorowaliśmy.
    shl rax, 1
    jnc top_bit_not_set
    xor rax, r8
top_bit_not_set:
    jmp bit_loop

next_byte:
    mov [rsi + rdx * 8], rax
    inc dl
    test dl, dl
    jnz lookup_loop ; jeśli dl == 0, to rozpatrzyliśmy już wszystkie bajty

    ; Główna pętla programu.
    xor r13, r13 ; przesunięcie początkowo wynosi 0
    xor rbx, rbx ; reszta CRC początkowo wynosi 0

main_do_while_loop:
    ; if (lseek(fd, offset, SEEK_CUR) < 0) exit(1)
    mov rax, SYS_LSEEK
    mov rsi, r13
    mov rdx, SEEK_CUR
    syscall
    test rax, rax
    js close_file_with_error

    ; Wczytuję długość fragmentu.
    lea rsi, [rel data_len]
    mov rdx, SIZEOF_DATA_LEN
    mov r10b, READ_DATA_LEN
    jmp read
data_len_has_been_read:
    movzx r12, word [rel data_len] ; r12 = *data_len

    ; Wczytuję fragment oraz przesunięcie.
    lea rsi, [rel data]
    lea rdx, [r12 + SIZEOF_OFFSET] ; rdx = data_len + SIZEOF_OFFSET
    xor r10b, r10b                 ; r10b = READ_DATA
    jmp read

data_has_been_read:
    lea rdx, [rel data]            ; rdx = fragment
    movsx r13, dword [rdx + r12]   ; r13 = offset

    ; Kontynuujemy obliczenia CRC w oparciu o wczytany fragment.
    ; rcx - indeks pętli
    ; rsi - adres tablicy crc_byte
    ; rdx - adres tablicy data
    ; for (rcx = 0; rcx < data_len; rcx++) {
    ;     al = data[rcx] ^ (rbx >> 56);
    ;     rbx = (rbx << 8) ^ crc_byte[al]
    ; }
    lea rsi, [rel crc_byte]
    xor rax, rax
    xor rcx, rcx

crc_loop:
    cmp rcx, r12
    jae end_crc_loop

    mov al, [rdx + rcx]
    mov r11, rbx
    shr r11, 56
    xor al, r11b ; xoruję fragment z najbardziej znaczącymi 8 bitami reszty CRC
    shl rbx, 8   ; zapominam o bitach sxorowanych z fragmentem
    xor rbx, [rsi + rax * 8] ; odczytuję wynik dzielenia z crc_byte[al]

    inc rcx
    jmp crc_loop
end_crc_loop:

    ; while (offset != -(data_len + 6)); (2 + 4 bajty na data_len i offset)
    lea rax, [r12 + r13 + 6]      ; rax = offset + (data_len + 6)
    test rax, rax
    jnz main_do_while_loop        ; jeśli rax == 0, to był ostatni fragment

    ; Koniec głównej pętli programu. Zamykam plik.
    ; if(close(fd) < 0) exit(1)
    mov rax, SYS_CLOSE
    syscall
    test rax, rax
    js exit_with_error

    ; Wpisuję wynik programu do bufora data.
    ; rax - adres tablicy data
    lea rax, [rel data]
    xor rcx, rcx

    ; for (rcx = 0; rcx < r9; rcx++) {
    ;     data[rcx] = '0' + (rbx & (1LL << 63));
    ;     rbx <<= 1;
    ; }
load_result_loop:
    mov byte [rax + rcx], 0
    shl rbx, 1
    adc byte [rax + rcx], ASCII_0
    inc rcx
    cmp rcx, r9
    jb load_result_loop

    mov byte [rax + rcx], ASCII_NEWLINE ; dopisuję na koniec znak nowej linii

    ; Wypisuję wynik na standardowe wyjście.
    ; rsi - adres na początek danych do wypisania
    ; rdx - liczba bajtów do wypisania
    ; while (rdx > 0) {
    ;     if ((rax = write(STDOUT_FILENO, data, rdx)) <= 0) exit(1);
    ;     rsi += rax;
    ;     rdx -= rax;
    ; }
    mov rdi, STDOUT
    lea rsi, [rel data]
    lea rdx, [r9 + 1]    ; rdx = r9 + 1, żeby wypisać też '\n'

write_result_loop:
    test rdx, rdx
    jz exit_with_success ; jeśli wypisano już całość
    mov rax, SYS_WRITE
    syscall
    test rax, rax
    jle exit_with_error  ; jeśli wypisano <= 0 bajtów
    add rsi, rax
    sub rdx, rax
    jmp write_result_loop

exit_with_success:
    xor rdi, rdi         ; rdi = EXIT_SUCCESS
    jmp exit

close_file_with_error:
    ; Zamknięcie pliku.
    mov rax, SYS_CLOSE
    syscall
    ; Nie sprawdzam, czy zamknięcie się powiodło - i tak kończę z kodem 1.

exit_with_error:
    mov rdi, EXIT_FAILURE

exit:
    ; Zakładam, że exit_code jest już w rdi.
    mov rax, SYS_EXIT
    syscall

; Pętla wczytująca daną liczbę bajtów z pliku pod zadany adres.
; Wczytuje korzystając (być może wielokrotnie) z funkcji systemowej sys_read.
; W przypadku niepowodzenia, kończy program z kodem 1.
; Zakłada poprawne wartości w rejestrach:
; rdi - deskryptor pliku
; rsi - bufor na dane (adres w pamięci)
; rdx - liczba bajtów do wczytania
; r10 - informacja, do którego miejsca w kodzie wrócić po skończonym wczytywaniu
; Zachowuje wartości wszystkich rejestrów poza rsi, rdx, rax.
; while (rdx > 0) {
;     if ((rax = read(rdi, rsi, rdx)) <= 0) exit(1);
;     rsi += rax;
;     rdx -= rax;
; }
read:
    test rdx, rdx
    jz return                 ; jeśli wczytano już wymaganą liczbę bajtów
    mov rax, SYS_READ
    syscall
    test rax, rax
    jle close_file_with_error ; jeśli wczytano <= 0 bajtów
    add rsi, rax
    sub rdx, rax
    jmp read

return:
    test r10b, r10b
    jz data_has_been_read     ; jeśli r10b = READ_DATA
    jl data_len_has_been_read ; jeśli r10b = READ_DATA_LEN

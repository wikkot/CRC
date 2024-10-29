Pliki z dziurami
--------------------

Pliki w Linuksie mogą być dziurawe. Na potrzeby tego zadania przyjmujemy, że plik z dziurami składa się z ciągłych fragmentów. Na początku fragmentu jest dwubajtowa długość w bajtach danych we fragmencie. Potem są dane. Fragment kończy się czterobajtowym przesunięciem, które mówi, o ile bajtów trzeba się przesunąć od końca tego fragmentu do początku następnego fragmentu. Długość danych w bloku jest 16-bitową liczbą w naturalnym kodzie binarnym. Przesunięcie jest 32-bitową liczbą w kodowaniu uzupełnieniowym do dwójki. Liczby w pliku zapisane są w porządku cienkokońcówkowym (ang. _little-endian_). Pierwszy fragment zaczyna się na początku pliku. Ostatni fragment rozpoznaje się po tym, że jego przesunięcie wskazuje na niego samego. Fragmenty w pliku mogą się stykać i nakładać.

Suma kontrolna pliku
--------------------

Sumę kontrolną pliku obliczamy za pomocą [cyklicznego kodu nadmiarowego](https://pl.wikipedia.org/wiki/Cykliczny_kod_nadmiarowy) (ang. _CRC_, _cyclic redundancy code_), biorąc pod uwagę dane w kolejnych fragmentach pliku. Dane pliku przetwarzamy bajtami. Przyjmujemy, że najbardziej znaczący bit bajtu z danymi i wielomianu (dzielnika) CRC zapisujemy po lewej stronie.

Polecenie
---------

Zaimplementuj w asemblerze program `crc`, który oblicza sumę kontrolną danych zawartych w podanym pliku z dziurami:

    ./crc file crc_poly
    

Parametr `file` to nazwa pliku. Parametr `crc_poly` to ciąg zer i jedynek opisujący wielomian CRC. Nie zapisujemy współczynika przy najwyższej potędze. Maksymalny stopień wielomianu CRC to 64 (maksymalna długość dzielnika CRC to 65). Przykładowo `11010101` oznacza wielomian $x^8+x^7+x^6+x^4+x^2+1$. Wielomian stały uznajemy za niepoprawny.

Program wypisuje na standardowe wyjście obliczoną sumę kontrolną jako napis składający się z zer i jedynek, zakończony znakiem nowego wiersza `\n`. Program sygnalizuje poprawne zakończenie kodem `0`.

Kompilowanie
------------

Rozwiązanie będzie kompilowane poleceniami:

    nasm -f elf64 -w+all -w+error -o crc.o crc.asm
    ld --fatal-warnings -o crc crc.o
    

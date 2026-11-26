// The nr/ files packed into the library (pack_files.py); engine.cpp's unpack() writes them out.
    .section .rodata
    .balign 16
    .global vana_nr_files
    .hidden vana_nr_files
vana_nr_files:
    .incbin NR_PACK
    .global vana_nr_files_end
    .hidden vana_nr_files_end
vana_nr_files_end:
    .section .note.GNU-stack,"",@progbits

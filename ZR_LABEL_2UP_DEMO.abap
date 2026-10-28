*&---------------------------------------------------------------------*
*& Report ZR_LABEL_2UP_DEMO
*&---------------------------------------------------------------------*
*& Demo: print N labels on A6 sheets that hold 2 labels each ("2-up").
*&
*& The trick is NOT in the ABAP: the program builds one internal table
*& with all labels and calls the Adobe Form ONCE. The form has two
*& content areas on the master page (top / bottom label) and a label
*& subform that repeats per table row and flows from one content area
*& to the next.
*&
*& Objects:
*&   ZS_LABEL_2UP_DEMO   structure  (MATNR, MAKTX)
*&   ZTT_LABEL_2UP_DEMO  table type of ZS_LABEL_2UP_DEMO
*&   ZAFI_LABEL_2UP_DEMO Adobe Form interface (IT_LABELS)
*&   ZAF_LABEL_2UP_DEMO  Adobe Form (A6, 2 content areas)
*&---------------------------------------------------------------------*
REPORT zr_label_2up_demo.

DATA gv_matnr TYPE matnr.

SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
  SELECT-OPTIONS s_matnr FOR gv_matnr.
  PARAMETERS p_qty  TYPE i DEFAULT 1.
  PARAMETERS p_form TYPE fpname DEFAULT 'ZAF_LABEL_2UP_DEMO'.
SELECTION-SCREEN END OF BLOCK b01.

*----------------------------------------------------------------------*
CLASS lcl_label_printer DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES tt_matnr_range TYPE RANGE OF matnr.

    CLASS-METHODS default_materials
      RETURNING VALUE(rt_matnr) TYPE tt_matnr_range.

    METHODS constructor
      IMPORTING it_matnr TYPE tt_matnr_range
                iv_qty   TYPE i
                iv_form  TYPE fpname.

    METHODS run.

  PRIVATE SECTION.
    DATA mt_matnr TYPE tt_matnr_range.
    DATA mv_qty   TYPE i.
    DATA mv_form  TYPE fpname.

    METHODS get_labels
      RETURNING VALUE(rt_labels) TYPE ztt_label_2up_demo.

    METHODS print
      IMPORTING it_labels TYPE ztt_label_2up_demo.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_label_printer IMPLEMENTATION.

  METHOD default_materials.
    " Replace with three materials that exist in your system
    TYPES tt_matnr_ext TYPE STANDARD TABLE OF char40 WITH EMPTY KEY.
    DATA lv_matnr TYPE matnr.

    DATA(lt_matnr_ext) = VALUE tt_matnr_ext( ( 'DEMO-MAT-01' )
                                             ( 'DEMO-MAT-02' )
                                             ( 'DEMO-MAT-03' ) ).

    LOOP AT lt_matnr_ext INTO DATA(lv_matnr_ext).
      " Material numbers are stored in internal format (MATN1)
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input        = lv_matnr_ext
        IMPORTING
          output       = lv_matnr
        EXCEPTIONS
          length_error = 1
          OTHERS       = 2.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_matnr ) TO rt_matnr.
    ENDLOOP.
  ENDMETHOD.

  METHOD constructor.
    mt_matnr = it_matnr.
    mv_qty   = iv_qty.
    mv_form  = iv_form.
  ENDMETHOD.

  METHOD run.
    DATA(lt_labels) = get_labels( ).

    IF lt_labels IS INITIAL.
      MESSAGE 'No materials found for the selection' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    print( lt_labels ).
  ENDMETHOD.

  METHOD get_labels.
    SELECT product            AS matnr,
           productdescription AS maktx
      FROM i_productdescription
      WHERE product  IN @mt_matnr
        AND language  = @sy-langu
      ORDER BY product
      INTO TABLE @DATA(lt_products).

    " One table row per physical label: quantity becomes data, not copies.
    " The form decides where each row lands (top or bottom of the sheet).
    LOOP AT lt_products INTO DATA(ls_product).
      DO mv_qty TIMES.
        APPEND VALUE #( matnr = ls_product-matnr
                        maktx = ls_product-maktx ) TO rt_labels.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.

  METHOD print.
    DATA ls_outputparams TYPE sfpoutputparams.
    DATA ls_docparams    TYPE sfpdocparams.
    DATA lv_fm_name      TYPE funcname.

    TRY.
        CALL FUNCTION 'FP_FUNCTION_MODULE_NAME'
          EXPORTING
            i_name     = mv_form
          IMPORTING
            e_funcname = lv_fm_name.
      CATCH cx_fp_api INTO DATA(lx_fp_api).
        MESSAGE lx_fp_api TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    " Print dialog lets the user pick device / preview.
    " Copies stay at 1: the label quantity is already in the data.
    ls_outputparams-nodialog = abap_false.
    ls_outputparams-copies   = 1.

    CALL FUNCTION 'FP_JOB_OPEN'
      CHANGING
        ie_outputparams = ls_outputparams
      EXCEPTIONS
        cancel          = 1
        usage_error     = 2
        system_error    = 3
        internal_error  = 4
        OTHERS          = 5.
    IF sy-subrc = 1.
      RETURN.                                " user cancelled the dialog
    ELSEIF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    ls_docparams-langu = sy-langu.

    " ONE call for all labels -> the form paginates 2 per sheet
    CALL FUNCTION lv_fm_name
      EXPORTING
        /1bcdwb/docparams = ls_docparams
        it_labels         = it_labels
      EXCEPTIONS
        usage_error       = 1
        system_error      = 2
        internal_error    = 3
        OTHERS            = 4.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 DISPLAY LIKE 'E'.
    ENDIF.

    CALL FUNCTION 'FP_JOB_CLOSE'
      EXCEPTIONS
        usage_error    = 1
        system_error   = 2
        internal_error = 3
        OTHERS         = 4.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
INITIALIZATION.
  s_matnr[] = lcl_label_printer=>default_materials( ).

AT SELECTION-SCREEN.
  IF p_qty NOT BETWEEN 1 AND 99.
    MESSAGE 'Quantity per material must be between 1 and 99' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  NEW lcl_label_printer( it_matnr = s_matnr[]
                         iv_qty   = p_qty
                         iv_form  = p_form )->run( ).

verdiWindowResize -win $_vdCoverage_1 "510" "190" "900" "700"
gui_set_pref_value -category {coveragesetting} -key {geninfodumping} -value 1
gui_exclusion -set_force true
verdiSetFont  -font  {DejaVu Sans}  -size  11
verdiSetFont -font "DejaVu Sans" -size "11"
gui_assert_mode -mode flat
gui_class_mode -mode hier
gui_excl_mgr_flat_list -on  0
gui_covdetail_select -id  CovDetail.1   -name   Line
verdiWindowWorkMode -win $_vdCoverage_1 -coverageAnalysis
verdiSetActWin -dock widgetDock_Message
gui_open_cov  -hier merged.vdb -testdir {} -test {merged/test} -merge MergedTest -db_max_tests 10 -sdc_level 1 -fsm transition
verdiWindowResize -win $_vdCoverage_1 "510" "169" "1015" "709"
gui_list_expand -id  CoverageTable.1   -list {covtblInstancesList} tb_top
verdiSetActWin -dock widgetDock_<Summary>
gui_list_expand -id  CoverageTable.1   -list {covtblInstancesList} tb_top.u_dut
gui_covtable_show -show  { Function Groups } -id  CoverageTable.1  -test  MergedTest
gui_covtable_show -show  { Design Hierarchy } -id  CoverageTable.1  -test  MergedTest
verdiSetActWin -dock widgetDock_<CovSrc.1>
vdCovExit -noprompt

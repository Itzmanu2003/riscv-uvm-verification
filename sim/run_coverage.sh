#!/bin/bash
# Run all tests with separate coverage databases, then merge
cd "$(dirname "$0")"

echo "=========================================="
echo "  Coverage Regression — Running All Tests"
echo "=========================================="

# Clean old databases
# NOTE: all runs write into the COMPILE-time database ./simv.vdb (it holds the
# design hierarchy); separate -cm_dir per run gives a merge with Groups only.
rm -rf cov_*.vdb merged.vdb urgReport cov_report simv.vdb/snps/coverage/db/testdata 2>/dev/null

TESTS=(
    "riscv_base_test 1"
    "riscv_muldiv_test 1"
    "riscv_loadstore_test 1"
    "riscv_coverage_test 1"
    "riscv_hazard_test 1"
    "riscv_random_test 1"
    "riscv_random_test 2"
    "riscv_random_test 3"
    "riscv_random_test 4"
    "riscv_random_test 5"
    "riscv_mega_test 1"
    "riscv_byte_half_test 1"
    "riscv_mext_test 1"
    "riscv_mext_test 2"
    "riscv_trap_test 1"
    "riscv_cache_stress_test 1"
    "riscv_extreme_test 1"
    "riscv_full_random_test 1"
    "riscv_full_random_test 2"
    "riscv_full_random_test 3"
    "riscv_full_random_test 4"
    "riscv_full_random_test 5"
    "riscv_reset_test 1"
)

i=0
for entry in "${TESTS[@]}"; do
    test=$(echo $entry | awk '{print $1}')
    seed=$(echo $entry | awk '{print $2}')
    i=$((i+1))
    echo -n "  [$i/${#TESTS[@]}] $test (seed=$seed) ... "
    ./simv +UVM_TESTNAME=$test +ntb_random_seed=$seed \
           -no_save -cm line+cond+fsm+tgl+branch \
           -cm_dir ./simv.vdb -cm_name ${test}_s${seed} -l run_cov_${i}.log > /dev/null 2>&1
    
    # Check pass/fail
    sb_fail=$(grep "SCOREBOARD SUMMARY" run_cov_${i}.log | grep -o "[0-9]* FAIL" | grep -o "[0-9]*")
    sb_fail=${sb_fail:-99}
    uvm_err=$(grep "^UVM_ERROR :" run_cov_${i}.log | grep -o "[0-9]*" | head -1)
    uvm_err=${uvm_err:-99}
    if [ "$sb_fail" = "0" ] && [ "$uvm_err" = "0" ]; then
        sb_pass=$(grep "SCOREBOARD SUMMARY" run_cov_${i}.log | grep -o "[0-9]* PASS" | grep -o "[0-9]*")
        echo "PASS (${sb_pass} checks)"
    else
        echo "FAIL"
    fi
done

echo ""
echo "=========================================="
echo "  Merging Coverage Databases"
echo "=========================================="

urg -dir simv.vdb -dbname merged.vdb -report cov_report -format both 2>/dev/null

if [ -d "merged.vdb" ]; then
    echo "  Merged database: merged.vdb"
    echo "  HTML report: cov_report/dashboard.html"
    echo ""
    echo "  Open in Verdi:  verdi -cov -covdir merged.vdb &"
    echo "  Open in browser: firefox cov_report/dashboard.html &"
else
    echo "  Merge completed. Report in cov_report/"
    echo "  Open: firefox cov_report/dashboard.html &"
fi

echo "=========================================="

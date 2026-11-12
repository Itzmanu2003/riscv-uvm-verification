TEST ?= riscv_random_test
SEED ?= 1
CM = line+cond+fsm+tgl+branch

VCS_FLAGS = -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
            -top tb_top -debug_access+all -kdb -lca \
            -cm $(CM)

SIM_FLAGS = -no_save -cm $(CM) -cm_dir ./simv.vdb

compile:
	vcs $(VCS_FLAGS) -f files.f -l compile.log
	@echo "--- compile errors (if any): ---"
	@grep "Error-" compile.log || echo "  none - compile clean"

run:
	./simv +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) $(SIM_FLAGS) -cm_test $(TEST)_s$(SEED) -l run.log
	@echo "--- scoreboard result: ---"
	@grep "SCOREBOARD SUMMARY\|COVERAGE" run.log

regress:
	./regress.sh 20

# new directed + random tests only (no coverage), e.g. "make newtests"
NEW_TESTS = riscv_byte_half_test riscv_mext_test riscv_trap_test riscv_cache_stress_test riscv_extreme_test riscv_full_random_test riscv_reset_test
newtests:
	@for t in $(NEW_TESTS); do \
	  ./simv +UVM_TESTNAME=$$t +ntb_random_seed=$(SEED) -no_save -l n_$$t.log > /dev/null; \
	  echo "$$t : `grep 'SCOREBOARD SUMMARY' n_$$t.log | sed 's/.*SUMMARY: //'`  `grep '^UVM_ERROR :' n_$$t.log`"; \
	done

covregress:
	@echo "=== Running all tests into simv.vdb ==="
	./simv +UVM_TESTNAME=riscv_base_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test base -l r_base.log
	./simv +UVM_TESTNAME=riscv_muldiv_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test muldiv -l r_muldiv.log
	./simv +UVM_TESTNAME=riscv_loadstore_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test loadstore -l r_loadstore.log
	./simv +UVM_TESTNAME=riscv_coverage_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test covtest -l r_covtest.log
	./simv +UVM_TESTNAME=riscv_hazard_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test hazard -l r_hazard.log
	./simv +UVM_TESTNAME=riscv_random_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test rand1 -l r_rand1.log
	./simv +UVM_TESTNAME=riscv_random_test +ntb_random_seed=2 $(SIM_FLAGS) -cm_test rand2 -l r_rand2.log
	./simv +UVM_TESTNAME=riscv_random_test +ntb_random_seed=3 $(SIM_FLAGS) -cm_test rand3 -l r_rand3.log
	./simv +UVM_TESTNAME=riscv_mega_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test mega -l r_mega.log
	./simv +UVM_TESTNAME=riscv_byte_half_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test byte_half -l r_byte_half.log
	./simv +UVM_TESTNAME=riscv_mext_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test mext -l r_mext.log
	./simv +UVM_TESTNAME=riscv_trap_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test trap -l r_trap.log
	./simv +UVM_TESTNAME=riscv_cache_stress_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test cache -l r_cache.log
	./simv +UVM_TESTNAME=riscv_extreme_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test extreme -l r_extreme.log
	./simv +UVM_TESTNAME=riscv_full_random_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test frand1 -l r_frand1.log
	./simv +UVM_TESTNAME=riscv_full_random_test +ntb_random_seed=2 $(SIM_FLAGS) -cm_test frand2 -l r_frand2.log
	./simv +UVM_TESTNAME=riscv_full_random_test +ntb_random_seed=3 $(SIM_FLAGS) -cm_test frand3 -l r_frand3.log
	./simv +UVM_TESTNAME=riscv_reset_test +ntb_random_seed=1 $(SIM_FLAGS) -cm_test reset -l r_reset.log
	@echo "=== Coverage regression done ==="
	@grep "SCOREBOARD SUMMARY" r_*.log
	@grep -L "UVM_ERROR :    0" r_*.log | sed 's/^/  UVM_ERROR in: /' || true

cov:
	verdi -cov -covdir simv.vdb &

report:
	urg -dir simv.vdb -report cov_report -format both
	@echo "Open cov_report/dashboard.html in a browser"

wave:
	verdi -ssf waves.fsdb &

clean:
	rm -rf simv simv.daidir csrc *.log simv.vdb cov_report waves.fsdb \
	       ucli.key vc_hdrs.h novas.* verdiLog DVEfiles cov_*.vdb merged.vdb

all: compile run

.PHONY: compile run regress newtests covregress cov report wave clean all

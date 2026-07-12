/*
 * mayhem/fuzz_load.c — in-process libFuzzer harness for libcyaml.
 *
 * Reuses the planner example's real-world schema (dates, enums, flags, bitfields,
 * sequences, strings, pointers) by including the example TU with its main() renamed
 * away — no duplicated schema, and upstream stays unmodified. Each input is loaded
 * with cyaml_load_data; on success it is re-saved with cyaml_save_data and both
 * allocations are released, exercising load, save, util, utf8, mem and free paths.
 */
#include <stddef.h>
#include <stdint.h>

#define main planner_example_main
#include "../examples/planner/main.c"
#undef main

static const cyaml_config_t fuzz_config = {
	.log_fn = NULL,               /* quiet: no logging during fuzzing */
	.mem_fn = cyaml_mem,
	.log_level = CYAML_LOG_ERROR,
};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct plan *plan = NULL;
	cyaml_err_t err;

	err = cyaml_load_data(data, size, &fuzz_config,
			&plan_schema, (cyaml_data_t **) &plan, NULL);
	if (err != CYAML_OK) {
		return 0;
	}

	char *yaml = NULL;
	size_t len = 0;
	err = cyaml_save_data(&yaml, &len, &fuzz_config, &plan_schema, plan, 0);
	if (err == CYAML_OK) {
		fuzz_config.mem_fn(fuzz_config.mem_ctx, yaml, 0);
	}

	cyaml_free(&fuzz_config, &plan_schema, plan, 0);
	return 0;
}

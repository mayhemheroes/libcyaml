/*
 * mayhem/fuzz_planner.c — in-process libFuzzer harness for the `planner` target.
 *
 * The fork's original `planner` target fuzzed the planner example CLI as a raw
 * file-input target (`planner @@ /tmp/out.yaml`). Its authoritative 300s run
 * completed with 0 edges, so it is re-ported as an in-process libFuzzer harness
 * over the SAME library code path the CLI drives: the input is staged to a /tmp
 * file, loaded with the example's own config + plan schema via cyaml_load_file(),
 * the loaded plan is walked and mutated like the example does, saved back out
 * with cyaml_save_file(), and freed. The example's schema/config definitions are
 * reused verbatim by including its source (main renamed away, unused). Unlike the
 * example's main(), the harness checks the loaded plan for NULL / empty tasks
 * before dereferencing — that unchecked dereference is the example app's own
 * (already-recorded) CWE-476, not library behavior the target should re-crash on
 * for every trivial input.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define main planner_example_main
#include "../examples/planner/main.c"
#undef main

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	static char in_path[64];
	static char out_path[64];
	struct plan *plan = NULL;
	cyaml_err_t err;
	FILE *f;

	snprintf(in_path, sizeof(in_path), "/tmp/planner_in_%d.yaml", getpid());
	snprintf(out_path, sizeof(out_path), "/tmp/planner_out_%d.yaml", getpid());

	f = fopen(in_path, "wb");
	if (f == NULL) {
		return 0;
	}
	if (size > 0 && fwrite(data, 1, size, f) != size) {
		fclose(f);
		return 0;
	}
	fclose(f);

	err = cyaml_load_file(in_path, &config, &plan_schema,
			(void **) &plan, NULL);
	if (err != CYAML_OK || plan == NULL) {
		return 0;
	}

	/* Use the data (as the example does, guarded). */
	if (plan->name != NULL) {
		(void) strlen(plan->name);
	}
	for (unsigned i = 0; i < plan->tasks_count; i++) {
		if (plan->tasks[i].name != NULL) {
			(void) strlen(plan->tasks[i].name);
		}
	}

	/* Modify the data (as the example does, guarded). */
	if (plan->tasks_count > 0) {
		plan->tasks[0].estimate.days += 3;
		plan->tasks[0].estimate.weeks += 1;
	}

	/* Save data to a new YAML file, then free it. */
	(void) cyaml_save_file(out_path, &config, &plan_schema, plan, 0);
	cyaml_free(&config, &plan_schema, plan, 0);
	return 0;
}

#include "bridge.h"
#include <rime_api.h>
#include <stdlib.h>
#include <string.h>

static RimeApi *api;
static bool ready;

bool live_start(const char *shared, const char *user) {
    if (api) return ready;
    api = rime_get_api();
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = shared;
    traits.user_data_dir = user;
    traits.app_name = "rime.lingolive";
    traits.distribution_name = "YuliuType";
    traits.distribution_code_name = "lingolive";
    traits.distribution_version = "1.0.0";
    traits.min_log_level = 3;
    api->setup(&traits);
    api->initialize(&traits);
    // First deployment builds the dictionary; later starts only check timestamps.
    if (api->start_maintenance(False)) api->join_maintenance_thread();
    RimeSessionId probe = api->create_session();
    if (!probe) return false;
    ready = api->select_schema(probe, "lingolive");
    api->destroy_session(probe);
    return ready;
}

LiveSession live_session(void) {
    if (!ready) return 0;
    RimeSessionId id = api->create_session();
    if (id && !api->select_schema(id, "lingolive")) {
        api->destroy_session(id);
        return 0;
    }
    return id;
}

void live_destroy(LiveSession id) { if (id) api->destroy_session(id); }
void live_clear(LiveSession id) { if (id) api->clear_composition(id); }
bool live_key(LiveSession id, int key) { return id && api->process_key(id, key, 0); }
bool live_choose(LiveSession id, int index) {
    return id && index >= 0 && api->select_candidate_on_current_page(id, (size_t)index);
}
bool live_page(LiveSession id, bool back) { return id && api->change_page(id, back); }

void live_candidates(LiveSession id, void *payload, LiveCandidateVisitor visit) {
    if (!id) return;
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(id, &context)) return;
    for (int i = 0; i < context.menu.num_candidates; ++i) {
        if (context.menu.candidates[i].text) visit(payload, context.menu.candidates[i].text);
    }
    api->free_context(&context);
}

char *live_raw(LiveSession id) {
    const char *value = id ? api->get_input(id) : NULL;
    return value ? strdup(value) : NULL;
}

char *live_commit(LiveSession id) {
    if (!id) return NULL;
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(id, &commit)) return NULL;
    char *copy = commit.text ? strdup(commit.text) : NULL;
    api->free_commit(&commit);
    return copy;
}

bool live_finish(LiveSession id) { return id && api->commit_composition(id); }

static char *copy_context_text(LiveSession id, bool preedit) {
    if (!id) return NULL;
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(id, &context)) return NULL;
    const char *value = preedit ? context.composition.preedit : context.commit_text_preview;
    char *copy = value ? strdup(value) : NULL;
    api->free_context(&context);
    return copy;
}

char *live_preedit(LiveSession id) { return copy_context_text(id, true); }
char *live_preview(LiveSession id) { return copy_context_text(id, false); }

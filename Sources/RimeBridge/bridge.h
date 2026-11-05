#include <stdbool.h>
#include <stdint.h>

typedef uintptr_t LiveSession;
typedef void (*LiveCandidateVisitor)(void *, const char *);

bool live_start(const char *shared, const char *user);
LiveSession live_session(void);
void live_destroy(LiveSession session);
void live_clear(LiveSession session);
bool live_key(LiveSession session, int key);
bool live_choose(LiveSession session, int index);
bool live_page(LiveSession session, bool back);
void live_candidates(LiveSession session, void *payload, LiveCandidateVisitor visit);
char *live_raw(LiveSession session);
char *live_commit(LiveSession session);
bool live_finish(LiveSession session);
char *live_preedit(LiveSession session);
char *live_preview(LiveSession session);

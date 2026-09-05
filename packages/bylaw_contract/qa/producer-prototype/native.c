#include <erl_nif.h>
#include <stdatomic.h>
#include <stdint.h>
typedef struct { int kind; ERL_NIF_TERM literal; unsigned int length, children[8]; } Node;
typedef struct { ERL_NIF_TERM module, function; unsigned int arity, argument, root; int event; } Rule;
typedef struct { unsigned int length, budget, node_count, flag_count; Rule rules[8]; Node nodes[64]; } Program;
typedef struct { _Atomic uint64_t calls; _Atomic uint64_t returns; uint64_t limit; _Atomic int reasons; _Atomic uint64_t hits[8]; int notify_release; ErlNifPid release_receiver; unsigned int list_budget; unsigned int slot_count; Program *program; } Counts;
enum { COUNTER_LIMIT = 1, INVALID_CLASSIFICATION = 2, CODE_CHANGE = 4, TRAVERSAL_BUDGET = 8 };
static ErlNifResourceType *type;
static _Atomic uint64_t live_count;
static ERL_NIF_TERM atom(ErlNifEnv *env, const char *name) { return enif_make_atom(env,name); }
static _Atomic uint64_t *hit_counter(Counts *counts,unsigned int slot) {
  return slot<8 ? &counts->hits[slot] : ((_Atomic uint64_t*)(counts+1))+(slot-8);
}
static size_t counter_bytes(unsigned int slots) { return sizeof(Counts)+(slots-8)*sizeof(_Atomic uint64_t); }
static ERL_NIF_TERM allocate_counts(ErlNifEnv *env,ErlNifUInt64 limit,ErlNifPid *receiver,unsigned int slots) {
  Counts *counts=enif_alloc_resource(type,counter_bytes(slots));
  if (!counts) return enif_raise_exception(env,atom(env,"out_of_memory"));
  atomic_init(&counts->calls,0); atomic_init(&counts->returns,0);
  counts->list_budget=0; counts->program=NULL; counts->slot_count=slots;
  counts->notify_release=(receiver!=NULL);
  if (receiver) counts->release_receiver=*receiver;
  counts->limit=limit; atomic_init(&counts->reasons,0);
  for (unsigned int i=0;i<slots;i++) atomic_init(hit_counter(counts,i),0);
  atomic_fetch_add(&live_count,1);
  ERL_NIF_TERM result=enif_make_resource(env,counts); enif_release_resource(counts); return result;
}
static ERL_NIF_TERM create(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 limit = UINT64_MAX;
  if (argc >= 1 && (!enif_get_uint64(env,argv[0],&limit) || limit == 0)) return enif_make_badarg(env);
  ErlNifPid receiver;
  if (argc == 2 && !enif_get_local_pid(env,argv[1],&receiver)) return enif_make_badarg(env);
  return allocate_counts(env,limit,argc==2 ? &receiver : NULL,8);
}
static ERL_NIF_TERM new_slots(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  unsigned int slots;
  if (!enif_get_uint(env,argv[0],&slots) || slots<8 || slots>64) return enif_make_badarg(env);
  return allocate_counts(env,UINT64_MAX,NULL,slots);
}
static ERL_NIF_TERM integer_list(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  unsigned int budget;
  if (!enif_get_uint(env,argv[0],&budget) || budget == 0 || budget > 4096) return enif_make_badarg(env);
  ERL_NIF_TERM result=create(env,0,argv);
  Counts *counts;
  if (enif_get_resource(env,result,type,(void**)&counts)) counts->list_budget=budget;
  return result;
}

static int parse_node(ErlNifEnv *env,Program *program,ERL_NIF_TERM term,unsigned int depth,unsigned int *index) {
  if (!depth || program->node_count==64) return 0;
  *index=program->node_count++;
  Node *node=&program->nodes[*index];
  const char *names[]={"integer","atom","binary","integer_list","empty_integer_list","singleton_integer_list","multiple_integer_list",NULL,"non_neg_integer","neg_integer","pos_integer"};
  for (int i=0;i<11;i++) if (names[i] && enif_is_identical(term,atom(env,names[i]))) { node->kind=i; return 1; }
  int arity;
  const ERL_NIF_TERM *items;
  if (!enif_get_tuple(env,term,&arity,&items) || arity!=2) return 0;
  if (enif_is_identical(items[0],atom(env,"literal_atom")) && enif_is_atom(env,items[1])) {
    node->kind=7; node->literal=items[1]; return 1;
  }
  if (!enif_is_identical(items[0],atom(env,"tuple"))) return 0;
  node->kind=11;
  ERL_NIF_TERM rest=items[1],head;
  while (!enif_is_empty_list(env,rest)) {
    if (node->length==8 || !enif_get_list_cell(env,rest,&head,&rest) ||
        !parse_node(env,program,head,depth-1,&node->children[node->length])) return 0;
    node->length++;
  }
  return 1;
}
static ERL_NIF_TERM plan(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Program program={0};
  if (argc==3 && (!enif_get_uint(env,argv[2],&program.flag_count) || program.flag_count>64)) return enif_make_badarg(env);
  if (!enif_get_uint(env,argv[1],&program.budget) || !program.budget || program.budget>4096) return enif_make_badarg(env);
  ERL_NIF_TERM rest=argv[0], head;
  while (!enif_is_empty_list(env,rest)) {
    int arity;
    const ERL_NIF_TERM *items;
    if (program.length==8 || !enif_get_list_cell(env,rest,&head,&rest) || !enif_get_tuple(env,head,&arity,&items) || arity!=6) return enif_make_badarg(env);
    Rule *rule=&program.rules[program.length++];
    if (!enif_is_atom(env,items[0]) || !enif_is_atom(env,items[1]) || !enif_get_uint(env,items[2],&rule->arity) || rule->arity>255 || !enif_get_uint(env,items[4],&rule->argument)) return enif_make_badarg(env);
    rule->module=items[0]; rule->function=items[1];
    if (enif_is_identical(items[3],atom(env,"call"))) rule->event=0;
    else if (enif_is_identical(items[3],atom(env,"return"))) rule->event=1;
    else return enif_make_badarg(env);
    if ((!rule->event && (!rule->argument || rule->argument>rule->arity)) || (rule->event && rule->argument)) return enif_make_badarg(env);
    if (!parse_node(env,&program,items[5],8,&rule->root)) return enif_make_badarg(env);
  }
  if (!program.length || program.length+program.flag_count>64) return enif_make_badarg(env);
  unsigned int slots=program.length+program.flag_count;
  ERL_NIF_TERM result=allocate_counts(env,UINT64_MAX,NULL,slots<8 ? 8 : slots);
  Counts *counts;
  if (!enif_get_resource(env,result,type,(void**)&counts)) return result;
  counts->program=enif_alloc(sizeof(Program));
  if (!counts->program) return enif_raise_exception(env,atom(env,"out_of_memory"));
  *counts->program=program;
  return result;
}

static ERL_NIF_TERM read_counts(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[0],type,(void**)&counts)) return enif_make_badarg(env);
  return enif_make_tuple2(env,enif_make_uint64(env,atomic_load(&counts->calls)),enif_make_uint64(env,atomic_load(&counts->returns)));
}
static ERL_NIF_TERM bytes(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[0],type,(void**)&counts)) return enif_make_badarg(env);
  return enif_make_uint64(env,counter_bytes(counts->slot_count)+(counts->program ? sizeof(Program) : 0));
}
static ERL_NIF_TERM status(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[0],type,(void**)&counts)) return enif_make_badarg(env);
  return atom(env,atomic_load(&counts->reasons) ? "incomplete" : "complete");
}
static ERL_NIF_TERM reasons(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[0],type,(void**)&counts)) return enif_make_badarg(env);
  int flags=atomic_load(&counts->reasons);
  const char *names[]={"counter_limit","invalid_classification","code_change","traversal_budget"};
  ERL_NIF_TERM result=enif_make_list(env,0);
  for (int i=3;i>=0;i--) if (flags & (1 << i)) result=enif_make_list_cell(env,atom(env,names[i]),result);
  return result;
}
static void increment(Counts *counts,_Atomic uint64_t *counter) {
  uint64_t value=atomic_load_explicit(counter,memory_order_relaxed);
  while (value < counts->limit) {
    if (atomic_compare_exchange_weak_explicit(counter,&value,value+1,memory_order_relaxed,memory_order_relaxed)) return;
  }
  atomic_fetch_or(&counts->reasons,COUNTER_LIMIT);
}

static int match_node(ErlNifEnv *env,Counts *counts,unsigned int index,ERL_NIF_TERM value,unsigned int *budget) {
  if (!*budget) { atomic_fetch_or(&counts->reasons,TRAVERSAL_BUDGET); return 0; }
  --*budget;
  Node *node=&counts->program->nodes[index];
  switch (node->kind) {
    case 0: return enif_term_type(env,value)==ERL_NIF_TERM_TYPE_INTEGER;
    case 1: return enif_is_atom(env,value);
    case 2: return enif_is_binary(env,value);
    case 7: return enif_is_identical(value,node->literal);
    case 8: case 9: case 10: {
      if (enif_term_type(env,value)!=ERL_NIF_TERM_TYPE_INTEGER) return 0;
      int sign=enif_compare(value,enif_make_int(env,0));
      return node->kind==8 ? sign>=0 : (node->kind==9 ? sign<0 : sign>0);
    }
    case 11: {
      int arity;
      const ERL_NIF_TERM *elements;
      if (!enif_get_tuple(env,value,&arity,&elements) || (unsigned int)arity!=node->length) return 0;
      for (unsigned int i=0;i<node->length;i++) if (!match_node(env,counts,node->children[i],elements[i],budget)) return 0;
      return 1;
    }
  }
  unsigned int length=0;
  while (!enif_is_empty_list(env,value)) {
    ERL_NIF_TERM head,tail;
    if (enif_term_type(env,value)!=ERL_NIF_TERM_TYPE_LIST) return 0;
    if (!*budget) { atomic_fetch_or(&counts->reasons,TRAVERSAL_BUDGET); return 0; }
    --*budget;
    if (!enif_get_list_cell(env,value,&head,&tail) || enif_term_type(env,head)!=ERL_NIF_TERM_TYPE_INTEGER) return 0;
    ++length; value=tail;
  }
  return node->kind==3 || (node->kind==4 && length==0) || (node->kind==5 && length==1) || (node->kind==6 && length>1);
}
static void execute_plan(ErlNifEnv *env,Counts *counts,ERL_NIF_TERM event,ERL_NIF_TERM options,int returning) {
  const ERL_NIF_TERM *mfa;
  int tuple_arity;
  unsigned int arity=0, budget=counts->program->budget;
  ERL_NIF_TERM values[255], result;
  if (!enif_get_tuple(env,event,&tuple_arity,&mfa) || tuple_arity!=3) goto invalid;
  if (returning) {
    if (!enif_get_uint(env,mfa[2],&arity) || arity>255 || !enif_get_map_value(env,options,atom(env,"extra"),&result)) goto invalid;
  } else {
    ERL_NIF_TERM rest=mfa[2];
    while (!enif_is_empty_list(env,rest)) {
      if (arity==255 || !enif_get_list_cell(env,rest,&values[arity],&rest)) goto invalid;
      ++arity;
    }
  }
  for (unsigned int i=0;i<counts->program->length;i++) {
    Rule *rule=&counts->program->rules[i];
    if (rule->event!=returning || rule->arity!=arity || !enif_is_identical(mfa[0],rule->module) || !enif_is_identical(mfa[1],rule->function)) continue;
    if (match_node(env,counts,rule->root,returning ? result : values[rule->argument-1],&budget)) increment(counts,hit_counter(counts,i));
  }
  return;
invalid:
  atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION);
}

static void classify_integer_list(ErlNifEnv *env,Counts *counts,ERL_NIF_TERM value,int slot) {
  unsigned int visited=0;
  while (!enif_is_empty_list(env,value)) {
    ERL_NIF_TERM head,tail;
    if (enif_term_type(env,value) != ERL_NIF_TERM_TYPE_LIST) return;
    if (visited == counts->list_budget) { atomic_fetch_or(&counts->reasons,TRAVERSAL_BUDGET); return; }
    if (!enif_get_list_cell(env,value,&head,&tail)) return;
    if (enif_term_type(env,head) != ERL_NIF_TERM_TYPE_INTEGER) return;
    value=tail; visited++;
  }
  increment(counts,&counts->hits[slot]);
}
static void classify_input(ErlNifEnv *env,Counts *counts,ERL_NIF_TERM event) {
  int arity;
  const ERL_NIF_TERM *mfa;
  ERL_NIF_TERM value,tail;
  if (!enif_get_tuple(env,event,&arity,&mfa) || arity != 3 ||
      !enif_get_list_cell(env,mfa[2],&value,&tail) || !enif_is_empty_list(env,tail)) {
    atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION); return;
  }
  classify_integer_list(env,counts,value,0);
}
static ERL_NIF_TERM hits(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[0],type,(void**)&counts)) return enif_make_badarg(env);
  ERL_NIF_TERM values[64];
  for (unsigned int i=0;i<counts->slot_count;i++) values[i]=enif_make_uint64(env,atomic_load(hit_counter(counts,i)));
  return enif_make_list_from_array(env,values,counts->slot_count);
}
static void classify(ErlNifEnv *env,Counts *counts,ERL_NIF_TERM options,unsigned int offset,unsigned int capacity,int required) {
  ERL_NIF_TERM result;
  if (!enif_get_map_value(env,options,atom(env,"match_spec_result"),&result)) {
    if (required) atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION);
    return;
  }
  int arity;
  const ERL_NIF_TERM *flags;
  if (!enif_get_tuple(env,result,&arity,&flags) || (unsigned int)arity > capacity || (required && (unsigned int)arity!=capacity)) {
    atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION); return;
  }
  for (int i=0;i<arity;i++) {
    if (!enif_is_identical(flags[i],atom(env,"true")) && !enif_is_identical(flags[i],atom(env,"false"))) {
      atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION); return;
    }
  }
  for (int i=0;i<arity;i++) if (enif_is_identical(flags[i],atom(env,"true"))) increment(counts,hit_counter(counts,offset+i));
}
static ERL_NIF_TERM enabled(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[1],type,(void**)&counts)) return atom(env,"remove");
  if (enif_is_identical(argv[0],atom(env,"call")) || enif_is_identical(argv[0],atom(env,"return_from")) || enif_is_identical(argv[0],atom(env,"trace_status"))) return atom(env,"trace");
  return atom(env,"discard");
}
static ERL_NIF_TERM trace(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  Counts *counts;
  if (!enif_get_resource(env,argv[1],type,(void**)&counts)) return atom(env,"ok");
  if (enif_is_identical(argv[0],atom(env,"call"))) {
    ERL_NIF_TERM classification;
    if (enif_get_map_value(env,argv[4],atom(env,"match_spec_result"),&classification) &&
        enif_is_identical(classification,atom(env,"producer_code_change"))) {
      atomic_fetch_or(&counts->reasons,CODE_CHANGE); return atom(env,"ok");
    }
    increment(counts,&counts->calls);
    if (counts->program) {
      execute_plan(env,counts,argv[3],argv[4],0);
      if (counts->program->flag_count) classify(env,counts,argv[4],counts->program->length,counts->program->flag_count,1);
    }
    else if (counts->list_budget) classify_input(env,counts,argv[3]);
    else classify(env,counts,argv[4],0,counts->slot_count,0);
  }
  if (enif_is_identical(argv[0],atom(env,"return_from"))) {
    increment(counts,&counts->returns);
    if (counts->program) execute_plan(env,counts,argv[3],argv[4],1);
    else if (counts->list_budget) {
      ERL_NIF_TERM value;
      if (enif_get_map_value(env,argv[4],atom(env,"extra"),&value)) classify_integer_list(env,counts,value,1);
      else atomic_fetch_or(&counts->reasons,INVALID_CLASSIFICATION);
    }
  }
  return atom(env,"ok");
}
static void destroy(ErlNifEnv *env,void *resource) {
  Counts *counts=resource;
  if (counts->program) enif_free(counts->program);
  atomic_fetch_sub(&live_count,1);
  if (counts->notify_release) enif_send(env,&counts->release_receiver,NULL,atom(env,"producer_resource_released"));
}
static ERL_NIF_TERM live_resources(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
  return enif_make_uint64(env,atomic_load(&live_count));
}
static int load(ErlNifEnv *env,void **private,ERL_NIF_TERM info) {
  type=enif_open_resource_type(env,NULL,"producer_counts",destroy,ERL_NIF_RT_CREATE,NULL);
  return type ? 0 : -1;
}
static ErlNifFunc functions[]={ {"new_slots",1,new_slots,0}, {"plan",3,plan,0}, {"plan",2,plan,0}, {"integer_list",1,integer_list,0},{"live_resources",0,live_resources,0},{"new",0,create,0},{"new",1,create,0},{"new",2,create,0},{"status",1,status,0},{"reasons",1,reasons,0},{"hits",1,hits,0},{"counts",1,read_counts,0},{"bytes",1,bytes,0},{"enabled",3,enabled,0},{"trace",5,trace,0} };
ERL_NIF_INIT(Elixir.ProducerNative,functions,load,NULL,NULL,NULL)

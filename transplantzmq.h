// from stddef.h:
#ifdef _WIN64
typedef unsigned __int64 size_t;
#elif defined _WIN32
typedef unsigned long size_t;
#else
typedef long unsigned int size_t;
#endif

// from zmq.h
int zmq_errno (void);

void *zmq_ctx_new (void);
int zmq_ctx_term (void *context);

typedef struct zmq_msg_t {unsigned char hidden [64];} zmq_msg_t;
int zmq_msg_init (zmq_msg_t *msg);
int zmq_msg_send (zmq_msg_t *msg, void *s, int flags);
int zmq_msg_recv (zmq_msg_t *msg, void *s, int flags);
int zmq_msg_close (zmq_msg_t *msg);
void *zmq_msg_data (zmq_msg_t *msg);

void *zmq_socket (void *, int type);
int zmq_close (void *s);
int zmq_connect (void *s, const char *addr);
int zmq_send (void *s, const void *buf, size_t len, int flags);

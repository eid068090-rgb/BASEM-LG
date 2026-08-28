#include <jni.h>
#include <arpa/inet.h>
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netpacket/packet.h>
#include <net/ethernet.h>
#ifndef ETH_P_ALL
#define ETH_P_ALL 0x0003
#endif
#include <sys/socket.h>
#include <sys/select.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <time.h>

static int u16(const unsigned char *p) { return ((int)p[0] << 8) | p[1]; }
static void macstr(const unsigned char *p, char *out) { sprintf(out, "%02x:%02x:%02x:%02x:%02x:%02x", p[0],p[1],p[2],p[3],p[4],p[5]); }
static void json_escape(const char *in, char *out, size_t cap) {
    size_t j=0; for(size_t i=0; in && in[i] && j+2<cap; i++) { unsigned char c=(unsigned char)in[i]; if(c=='"'||c=='\\') { out[j++]='\\'; out[j++]=c; } else if(c>=32 && c<127) out[j++]=c; else if(c=='\n'||c=='\r'||c=='\t') out[j++]=' '; } out[j]=0;
}
static void textval(const unsigned char *p, int n, char *out, size_t cap) { int m=n; while(m>0 && (p[m-1]==0 || isspace(p[m-1]))) m--; if(m >= (int)cap) m=(int)cap-1; memcpy(out,p,m); out[m]=0; for(int i=0;i<m;i++) if((unsigned char)out[i]<32) out[i]=' '; }
static int looks_mac(const char *s) { int n=0; for(;*s;s++) if(isxdigit((unsigned char)*s)) n++; return n==12; }

static void add_json(char *buf, size_t cap, int *count, const char *name, const char *proto, const char *port, const char *iface, const char *desc, const char *mgmt, const char *chassis, const char *src) {
    if(*count>0) strncat(buf, ",", cap-strlen(buf)-1);
    char e1[256],e2[512],e3[256],e4[256],e5[512],e6[128],e7[128];
    json_escape(name,e1,sizeof(e1)); json_escape(proto,e2,sizeof(e2)); json_escape(port,e3,sizeof(e3)); json_escape(iface,e4,sizeof(e4)); json_escape(desc,e5,sizeof(e5)); json_escape(mgmt,e6,sizeof(e6)); json_escape(chassis,e7,sizeof(e7));
    char item[1800]; snprintf(item,sizeof(item),"{\"name\":\"%s\",\"protocol\":\"%s\",\"port\":\"%s\",\"interface\":\"%s\",\"description\":\"%s\",\"managementIp\":\"%s\",\"chassisId\":\"%s\",\"srcMac\":\"%s\"}",e1,e2,e3,e4,e5,e6,e7,src);
    strncat(buf,item,cap-strlen(buf)-1); (*count)++;
}

static void parse_lldp(const unsigned char *d, int len, const char *iface, char *out, size_t cap, int *count) {
    if(len<14) return; char src[32]; macstr(d+6,src); int p=14; char chassis[128]="",port[256]="",name[256]="",desc[512]="",mgmt[64]="";
    while(p+2<=len) { int h=u16(d+p); p+=2; int type=h>>9, n=h&0x1ff; if(p+n>len) break; if(type==0) break;
        if(type==1 && n>=2) { int st=d[p]; if(st==4 && n>=7) macstr(d+p+1,chassis); else textval(d+p+1,n-1,chassis,sizeof(chassis)); }
        else if(type==2 && n>=2) { textval(d+p+1,n-1,port,sizeof(port)); }
        else if(type==5) textval(d+p,n,name,sizeof(name));
        else if(type==6) textval(d+p,n,desc,sizeof(desc));
        else if(type==8 && n>=6) { int al=d[p]; if(al>=5 && d[p+1]==1) snprintf(mgmt,sizeof(mgmt),"%u.%u.%u.%u",d[p+2],d[p+3],d[p+4],d[p+5]); }
        p+=n;
    }
    if(name[0]||chassis[0]||desc[0]) add_json(out,cap,count,name[0]?name:chassis,"LLDP",port,iface,desc,mgmt,looks_mac(chassis)?chassis:src,src);
}

static void parse_cdp(const unsigned char *d, int len, int start, const char *iface, char *out, size_t cap, int *count) {
    if(start+8>len) return; char src[32]; macstr(d+6,src); int p=start+4; char device[256]="",name[256]="",port[256]="",desc[512]="",mgmt[64]="";
    while(p+4<=len) { int type=u16(d+p), n=u16(d+p+2); if(n<4 || p+n>len) break; int v=p+4, m=n-4;
        if(type==0x0001) textval(d+v,m,device,sizeof(device));
        else if(type==0x0002) textval(d+v,m,name,sizeof(name));
        else if(type==0x0003 && m>=4) { for(int i=v;i+3<v+m;i++){ unsigned int a=d[i],b=d[i+1],c=d[i+2],e=d[i+3]; if(a>0&&a<224){snprintf(mgmt,sizeof(mgmt),"%u.%u.%u.%u",a,b,c,e);break;} } }
        else if(type==0x0006) textval(d+v,m,port,sizeof(port));
        else if(type==0x0009) textval(d+v,m,desc,sizeof(desc));
        else if(type==0x000b && !name[0]) textval(d+v,m,name,sizeof(name));
        p+=n;
    }
    if(name[0]||device[0]||desc[0]) add_json(out,cap,count,name[0]?name:device,"CDPv2",port,iface,desc,mgmt,looks_mac(device)?device:src,src);
}

JNIEXPORT jstring JNICALL Java_com_basemlg_basem_1lg_RawL2Native_capture(JNIEnv *env, jclass cls, jint durationMs, jint maxFrames) {
    (void)cls; if(durationMs<1000) durationMs=1000; if(maxFrames<1) maxFrames=1;
    size_t cap=1024*1024; char *json=calloc(1,cap); if(!json) return (*env)->NewStringUTF(env,"{\"frames\":[],\"rootRequired\":true}");
    strcpy(json,"{\"frames\":["); int count=0; int opened=0;
    struct ifaddrs *ifa0=NULL; if(getifaddrs(&ifa0)==0) {
        for(struct ifaddrs *ifa=ifa0; ifa && count<maxFrames; ifa=ifa->ifa_next) {
            if(!ifa->ifa_name || !ifa->ifa_addr) continue; unsigned int flags=ifa->ifa_flags; if(!(flags&IFF_UP) || (flags&IFF_LOOPBACK)) continue;
            if(strncmp(ifa->ifa_name,"wlan",4)&&strncmp(ifa->ifa_name,"eth",3)&&strncmp(ifa->ifa_name,"en",2)&&strncmp(ifa->ifa_name,"ap",2)) continue;
            int fd=socket(AF_PACKET,SOCK_RAW,htons(ETH_P_ALL)); if(fd<0) continue; opened=1;
            struct sockaddr_ll sll; memset(&sll,0,sizeof(sll)); sll.sll_family=AF_PACKET; sll.sll_protocol=htons(ETH_P_ALL); sll.sll_ifindex=if_nametoindex(ifa->ifa_name);
            if(bind(fd,(struct sockaddr*)&sll,sizeof(sll))<0){close(fd);continue;}
            struct timeval tv; tv.tv_sec=0; tv.tv_usec=250000; unsigned char buf[65536]; long long end=(long long)time(NULL)*1000+durationMs;
            while(count<maxFrames && (long long)time(NULL)*1000<end) { fd_set rf; FD_ZERO(&rf);FD_SET(fd,&rf);int r=select(fd+1,&rf,NULL,NULL,&tv); if(r<=0) continue; int n=recvfrom(fd,buf,sizeof(buf),0,NULL,NULL); if(n<14) continue; int et=u16(buf+12); if(et==ETH_P_LLDP) parse_lldp(buf,n,ifa->ifa_name,json,cap,&count); else if(et==ETH_P_CDP) parse_cdp(buf,n,14,ifa->ifa_name,json,cap,&count); else if(n>=22 && buf[14]==0xaa && buf[15]==0xaa && buf[16]==3 && buf[17]==0 && buf[18]==0 && buf[19]==0x0c && buf[20]==0x20 && buf[21]==0) parse_cdp(buf,n,22,ifa->ifa_name,json,cap,&count); }
            close(fd);
        }
        freeifaddrs(ifa0);
    }
    strncat(json,"],\"rootRequired\":",cap-strlen(json)-1); strncat(json,(!opened?"true":"false"),cap-strlen(json)-1); strncat(json,"}",cap-strlen(json)-1);
    jstring ret=(*env)->NewStringUTF(env,json); free(json); return ret;
}

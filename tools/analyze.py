import json,sys,statistics as st,collections
d=json.load(open(sys.argv[1]))
for k in('glRenderer','inner','canvas','sys','display'):print(k,d.get(k))
def rep(n,x):
    if not x:return
    s=sorted(x);print('%-10s n=%d mean=%.1f med=%.1f p95=%.1f p99=%.1f max=%.1f sd=%.1f'%(n,len(x),st.mean(x),s[len(s)//2],s[int(len(s)*.95)],s[int(len(s)*.99)],s[-1],st.pstdev(x)))
rep('rAF dt',d['deltas']);rep('run',d['work']);rep('update',d.get('upd'));rep('draw',d.get('drw'))
x=d['deltas'];print('fps',round(1000/st.mean(x),1),'frames >33ms: %.1f%%'%(100*sum(v>33.4 for v in x)/len(x)),'>50ms: %.1f%%'%(100*sum(v>50 for v in x)/len(x)))

cimport cython
from libc.math cimport exp,pow,fabs,log,sqrt,sinh,tgamma
cdef double pi=3.1415926535897932384626433832795028841971693993751058209749445923078164062
import numpy as np
cimport numpy as np
from math import ceil
from .common import *

cdef double badvalue = 1e-300
cdef double smallestdiv = 1e-10
cdef double smallestln = 0.
cdef double largestpow = 200
cdef double maxnegexp = 200
cdef class Normalize

def merge_func_code(f,g):
    nf = f.func_code.co_argcount
    farg = f.func_code.co_varnames[:nf]
    ng = g.func_code.co_argcount
    garg = g.func_code.co_varnames[:ng]
    
    mergearg = []
    #TODO: do something smarter
    #first merge the list
    for v in farg:
        mergearg.append(v)
    for v in garg:
        if v not in farg:
            mergearg.append(v)
    
    #now build the map
    fpos=[]
    gpos=[]
    for v in farg:
        fpos.append(mergearg.index(v))
    for v in garg:
        gpos.append(mergearg.index(v))
    return MinimalFuncCode(mergearg),np.array(fpos,dtype=np.int),np.array(gpos,dtype=np.int)

def construct_arg(arg,fpos):
    ret = list()
    for i in fpos: ret.append(arg[i])
    return tuple(ret)

def adjusted_bound(bound,bw):
    numbin = ceil((bound[1]-bound[0])/bw)
    return (bound[0],bound[0]+numbin*bw),numbin
    
cdef class Convolve:#with gy cache
    """
    Convolve)
    """
    cdef int numbins
    cdef tuple gbound
    cdef double bw
    cdef int nbg
    cdef f #original f
    cdef g #original g
    cdef vf #vectorized f
    cdef vg #vectorized g
    cdef np.ndarray fpos#position of argument in f
    cdef np.ndarray gpos#position of argument in g
    cdef public object func_code
    cdef public object func_defaults
    cdef tuple last_garg
    cdef np.ndarray gy_cache
    #g is resolution function gbound need to be set so that the end of g is zero
    def __init__(self,f,g,gbound,nbins=1000):
        self.vf = np.vectorize(f)
        self.vg = np.vectorize(g)
        self.set_gbound(gbound,nbins)
        self.func_code, self.fpos, self.gpos = merge_func_code(f,g)
        self.func_defaults = None

    def set_gbound(self,gbound,nbins):
        self.last_garg = None
        self.gbound,self.nbg = gbound,nbins
        self.bw = 1.0*(gbound[1]-gbound[0])/nbins
        self.gy_cache = None
    def __call__(self,*arg):
        #skip the first one
        cdef int iconv
        cdef double ret = 0
        cdef np.ndarray[np.double_t] gy,fy
        
        tmp_arg = arg[1:]
        x=arg[0]
        garg = list()

        for i in self.gpos: garg.append(arg[i])
        garg = tuple(garg[1:])#dock off the dependent variable
        
        farg = list()
        for i in self.fpos: farg.append(arg[i])
        farg = tuple(farg[1:])
        
        xg = np.linspace(self.gbound[0],self.gbound[1],self.nbg)

        gy = None
        #calculate all the g needed
        if garg==self.last_garg:
            gy = self.gy_cache
        else:
            gy = self.vg(xg,*garg)
            self.gy_cache=gy
        
        #now prepare f... f needs to be calculated and padded to f-gbound[1] to f+gbound[0]
        #yep this is not a typo because we are "reverse" sliding g onto f so we need to calculate f from
        # f-right bound of g to f+left bound of g
        fbound = x-self.gbound[1], x-self.gbound[0] #yes again it's not a typo
        xf = np.linspace(fbound[0],fbound[1],self.nbg)#yep nbg
        fy = self.vf(xf,*farg)
        #print xf[:100]
        #print fy[:100]
        #now do the inverse slide g and f
        for iconv in range(self.nbg):
            ret+=fy[iconv]*gy[self.nbg-iconv-1]
        
        #now normalize the integral
        ret*=self.bw
        
        return ret

cdef class Polynomial:
    cdef int order
    cdef public object func_code
    cdef public object func_defaults
    def __init__(self,order,xname='x'):
        """
        User can supply order as integer in which case it uses (c_0....c_n+1) default
        or the list of coefficient name which the first one will be the lowest order and the last one will be the highest order
        """
        varnames = None
        argcount = 0
        if isinstance(order, int):
            if order<0 : raise ValueError('order must be >=0')
            self.order = order
            varnames = ['c_%d'%i for i in range(order+1)]
        else: #use supply list of coeffnames #to do check if it's list of string
            if len(order)<=0: raise ValueError('need at least one coefficient')
            self.order=len(order)-1 #yep -1 think about it
            varnames = order
        varnames.insert(0,xname) #insert x in front
        self.func_code = MinimalFuncCode(varnames)
        self.func_defaults = None
    
    def __call__(self,*arg):
        cdef double x = arg[0]
        cdef double t
        cdef double ret=0.
        cdef int iarg
        cdef int numarg = self.order+1 #number of coefficient
        cdef int i
        for i in range(numarg):
            iarg = i+1
            t = arg[iarg]
            if i > 0:
                ret+=pow(x,i)*t
            else:#avoid 0^0
                ret += t
        return ret

#peaking stuff
@cython.binding(True)
def doublegaussian(double x, double mean, double sigmal, double sigmar):
    """
    unnormed gaussian normalized
    """
    cdef double ret = 0
    if sigma < smallestdiv:
        ret = badvalue
    else:
        d = (x-mean)/sigma
        d2 = d*d
        ret = exp(-0.5*d2)
    return ret

#peaking stuff
@cython.binding(True)
def ugaussian(double x, double mean, double sigma):
    """
    unnormed gaussian normalized
    """
    cdef double ret = 0
    if sigma < smallestdiv:
        ret = badvalue
    else:
        d = (x-mean)/sigma
        d2 = d*d
        ret = exp(-0.5*d2)
    return ret

@cython.binding(True)
def gaussian(double x, double mean, double sigma):
    """
    gaussian normalized for -inf to +inf
    """
    cdef double badvalue = 1e-300
    cdef double ret = 0
    if sigma < smallestdiv:
        ret = badvalue
    else:
        d = (x-mean)/sigma
        d2 = d*d
        ret = 1/(sqrt(2*pi)*sigma)*exp(-0.5*d2)
    return ret

@cython.binding(True)
def crystalball(double x,double alpha,double n,double mean,double sigma):
    """
    unnormalized crystal ball function 
    see http://en.wikipedia.org/wiki/Crystal_Ball_function
    """
    cdef double d
    cdef double ret = 0
    cdef double A = 0
    cdef double B = 0
    if sigma < smallestdiv:
        ret = badvalue
    elif fabs(alpha) < smallestdiv:
        ret = badvalue
    elif n<1.:
        ret = badvalue
    else:
        d = (x-mean)/sigma
        if d > -alpha : 
            ret = exp(-0.5*d**2)
        else:
            al = fabs(alpha)
            A=pow(n/al,n)*exp(-al**2/2.)
            B=n/al-al
            ret = A*pow(B-d,-n)
    return ret

#Background stuff
@cython.binding(True)
def argus(double x, double c, double chi, double p):
    """
    unnormalized argus distribution
    see: http://en.wikipedia.org/wiki/ARGUS_distribution
    """
    if c<smallestdiv:
        return badvalue
    if x>c:
        return 0.
    cdef double xc = x/c
    cdef double xc2 = xc*xc
    cdef double ret = 0
    
    ret = xc/c*pow(1.-xc2,p)*exp(-0.5*chi*chi*(1-xc2))
    
    return ret

#Polynomials
@cython.binding(True)
def linear(double x, double m, double c):
    """
    y=mx+c
    """
    cdef double ret = m*x+c
    return ret

@cython.binding(True)
def poly2(double x, double a, double b, double c):
    """
    y=ax^2+bx+c
    """
    cdef double ret = a*x*x+b*x+c
    return ret

@cython.binding(True)
def poly3(double x, double a, double b, double c, double d):
    """
    y=ax^2+bx+c
    """
    cdef double x2 = x*x
    cdef double x3 = x2*x
    cdef double ret = a*x3+b*x2+c*x+d
    return ret

@cython.binding(True)
def novosibirsk(double x, double width, double peak, double tail):
    #credit roofit implementation
    cdef double qa
    cdef double qb
    cdef double qc
    cdef double qx
    cdef double qy
    cdef double xpw
    cdef double lqyt
    if width < smallestdiv: return badvalue
    xpw = (x-peak)/width
    if fabs(tail) < 1e-7:
        qc = 0.5*xpw*xpw
    else:
        qa = tail*sqrt(log(4.))
        if qa < smallestdiv: return badvalue
        qb = sinh(qa)/qa
        qx = xpw*qb
        qy = 1.+tail*qx
        if qy > 1e-7:
            lqyt = log(qy)/tail
            qc =0.5*lqyt*lqyt + tail*tail
        else:
            qc=15.
    return exp(-qc)

# cdef class AddRaw:
#     cdef int nf
#     cdef object fs
#     cdef public object func_code
#     cdef public object func_defaults
#     def __init__(self,fs,coeffname):
#         pass
# cdef class AddAndRenorm
#     pass
cdef class Extend:
    """
    f = lambda x,y: x+y
    g = Extend(f) ==> g = lambda x,y,N: f(x,y)*N
    """
    cdef f
    cdef public func_code
    cdef public func_defaults
    def __init__(self,f,extname='N'):
        self.f = f
        if extname in f.func_code.co_varnames[:f.func_code.co_argcount]:
            raise ValueError('%s is already taken pick something else for extname')
        self.func_code = FakeFuncCode(f,append=extname)
        #print self.func_code.__dict__
        self.func_defaults=None
    def __call__(self,*arg):
        cdef double N = arg[-1]
        cdef double fval = self.f(*arg[:-1])
        return N*fval

cdef class Add2Pdf:
    cdef public object func_code
    cdef public object func_defaults
    cdef f
    cdef g
    cdef fpos
    cdef gpos

    def __init__(self,f,g):
        self.func_code, self.fpos, self.gpos = merge_func_code(f,g)
        self.func_defaults=None
        self.f=f
        self.g=g

    def __call__(self,*arg):
        farg = construct_arg(arg,self.fpos)
        garg = construct_arg(arg,self.gpos)
        return self.f(*farg)+self.g(*garg)

cdef class Add2PdfNorm:
    cdef public object func_code
    cdef public object func_defaults
    cdef f
    cdef g
    cdef fpos
    cdef gpos
    
    def __init__(self,f,g,facname='k_f'):
        self.func_code, self.fpos, self.gpos = merge_func_code(f,g)
        self.func_code.append(facname)
        self.func_defaults=None
        self.f=f
        self.g=g
    
    def __call__(self,*arg):
        fac = arg[-1]
        farg = construct_arg(arg,self.fpos)
        garg = construct_arg(arg,self.gpos)
        return fac*self.f(*farg)+(1.-fac)*self.g(*garg)

cdef class Normalize:
    cdef f
    cdef double norm_cache
    cdef tuple last_arg
    cdef int nint
    cdef np.ndarray midpoints
    cdef np.ndarray binwidth
    cdef public object func_code
    cdef public object func_defaults
    cdef int ndep
    cdef int warnfloat
    cdef int floatwarned
    def __init__(self,f,range,prmt=None,nint=1000,normx=None,warnfloat=1):
        """
        normx [optional array] adaptive step for dependent variable
        """
        self.f = f
        self.norm_cache= 1.
        self.last_arg = None
        self.nint = normx.size() if normx is not None else nint
        normx = normx if normx is not None else np.linspace(range[0],range[1],nint)
        if normx.dtype!=normx.dtype:
            normx = normx.astype(np.float64)
        #print range
        #print normx
        self.midpoints = mid(normx)
        #print self.midpoints
        self.binwidth = np.diff(normx)
        self.func_code = FakeFuncCode(f,prmt)
        self.ndep = 1#TODO make the code doesn't depend on this assumption
        self.func_defaults = None #make vectorize happy
        self.warnfloat=warnfloat
        self.floatwarned=0
    def __call__(self,*arg):
        #print arg
        cdef double n 
        cdef double x
        n = self._compute_normalization(*arg)
        x = self.f(*arg)
        if self.floatwarned < self.warnfloat  and n < 1e-100: 
            print 'Potential float erorr:', arg
            self.floatwarned+=1
        return x/n

    def _compute_normalization(self,*arg):
        cdef tuple targ = arg[self.ndep:]
        if targ == self.last_arg:#cache hit
            #yah exact match for float since this is expected to be used
            #in vectorize which same value are passed over and over
            pass
        else:
            self.last_arg = targ
            self.norm_cache = integrate1d(self.f,self.nint,self.midpoints,self.binwidth,targ)
        return self.norm_cache

#to do runge kutta or something smarter
def integrate1d(f, int nint, np.ndarray[np.double_t] midpoints, np.ndarray[np.double_t] binwidth, tuple arg=None):
    cdef double ret = 0
    cdef double bw = 0
    cdef double mp =0
    cdef int i=0
    cdef double x=0
    cdef double mpi=0
    if arg is None: arg = tuple()
    #print midpoints
    #mid point sum
    for i in range(nint-1):#mid has 1 less
        bw = binwidth[i]
        mp = midpoints[i]
        x = f(mp,*arg)

        ret += x*bw
        #print mp,bw,mpi,x,ret
    return ret
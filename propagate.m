%% Fresnel Propagation Function for CPU/GPU.
% Version 5.1
% The Fresnel appoximation describes how the image from an object gets
% propagated in real space.
% This function produces the digital refocusing of a hologram.
% (ref pg 67,J Goodman, Introduction to Fourier Optics)
% Version 5 works on CUDA enabled GPU if available.
% function [Eout,H] = propagate(Ein,lambda,Z,ps,zpad)
% inputs:
%         Ein    - complex field at input plane
%         lambda - wavelength of light [m]
%         Z      - vector of propagation distances [m], (can be negative)
%                  i.e. "linspace(0,10E-3,500)" or "0.01"
%         ps     - pixel size [m]
% optional inputs:
%         'zpad' - size of propagation kernel desired in pixels
%                  i.e.  'zpad',1024  or 'zpad',2048
%         'cpu'  - forces use of CPU, even if a CUDA GPU is available
%         'mask' - Allows for using a coded aperture mask. Mask image must
%                  be same size as padded image, i.e. 'mask',mask
% outputs:
%         Eout   - propagated complex field
%         H      - propagation kernel to check for aliasing
%
% Daniel Shuldman, UC Berkeley, eliasds@gmail.com


function [Eout,H] = propagate(Ein,lambda,Z,ps,varargin)

% Set Defaults and detect GPU and initial image size
[m,n] = size(Ein);  M = m;  N = n;
mask = 1; %Default Aperture Mask function
tfc = ones(size(Z));
try
    gpu_num = gpuDeviceCount; %Determines if there is a CUDA enabled GPU
catch err
    gpu_num = 0;
end

if nargin==3
    ps=6.5e-6;
elseif nargin==2
    ps=6.5e-6;
    Z=0;
elseif nargin==1
    ps=6.5e-6;
    Z=0;
    lambda=632.8e-9;
elseif nargin<1
    ps=6.5e-6;
    Z=0;
    lambda=632.8e-9;
    Ein=phantom;
end

if max(size(varargin))==1&&isnumeric(varargin{1})&&isscalar(varargin{1})
        zpad=varargin{1};
        varargin(1) = [];
        M=zpad;
        N=zpad;
end
        
while ~isempty(varargin)
    switch upper(varargin{1})
        
        case 'ZPAD'
            zpad = varargin{2};
            varargin(1:2) = [];
            M=zpad;
            N=zpad;
            
        case 'CPU'
            varargin(1) = [];
            gpu_num = 0;
            
        case 'MASK'
            mask = varargin{2};
            varargin(1:2) = [];
            
        case 'TFC' % Adds The Correct Transfer Function Coefficient (slower)
            % Default Behavoir leaves this as unity
            tfc = exp(1i*(2*pi/lambda)*Z);
            varargin(1) = [];
            
        otherwise
            error(['Unexpected option: ' varargin{1}])
    end
end


% Initialize variables into CPU or GPU
if gpu_num == 0;
    Eout = zeros(m,n,length(Z));
    aveborder=mean(cat(2,Ein(1,:),Ein(m,:),Ein(:,1)',Ein(:,n)'));
    if nargout>1
        H = zeros(M,N,length(Z));
    end
else
    % reset(gpuDevice(1));
    lambda = gpuArray(lambda);
    Z = gpuArray(Z);
    ps = gpuArray(ps);
    Eout = gpuArray.zeros(m,n,length(Z));
    aveborder=gpuArray(mean(cat(2,Ein(1,:),Ein(m,:),Ein(:,1)',Ein(:,n)')));
    if nargout>1
        H = gpuArray.zeros(M,N,length(Z));
    end
end
%k=(2*pi/lambda);  %wavenumber


% Spatial Sampling
[x,y]=meshgrid(-N/2:(N/2-1), -M/2:(M/2-1));
fx=(x/(ps*M));    %frequency space width [1/m]
fy=(y/(ps*N));    %frequency space height [1/m]
fx2fy2 = fx.^2 + fy.^2;


% Padding value 
Ein_pad=ones(M,N)*aveborder; %pad by average border value to avoid sharp jumps
Ein_pad(1+(M-m)/2:(M+m)/2,1+(N-n)/2:(N+n)/2)=Ein;


% FFT of E0
E0fft = fftshift(fft2(Ein_pad));
for z = 1:length(Z)
    %h(:,:,z) = exp(1i*(2*pi/lambda)*z)*exp(1i*(2*pi/lambda)*(x.^2+y.^2)/(2*z))/(1i*lambda*z); %Fresnel kernel
    H  = tfc(z)*exp(-1i*pi*lambda*Z(z)*fx2fy2); %Fast Transfer Function
    Eout_pad=ifft2(ifftshift(E0fft.*H.*mask));

    Eout(:,:,z)=Eout_pad(1+(M-m)/2:(M+m)/2,1+(N-n)/2:(N+n)/2);
end


% Gather variables from GPU if necessary
if gpu_num > 0;
    Eout=gather(Eout);
    if nargout > 1
        H=gather(H);
    end
end

%
% function mlmc_test2(mlmc_l, M,L, M0,Eps,Lmin,Lmax, fp)
%
% multilevel Monte Carlo test routine
%
% [sums cost] = mlmc_l(l,M)     low-level routine
%
% inputs:  l = level
%          M = number of paths
%
% output: sums(1) = sum(Pf-Pc)
%         sums(2) = sum((Pf-Pc).^2)
%         sums(3) = sum((Pf-Pc).^3)
%         sums(4) = sum((Pf-Pc).^4)
%         sums(5) = sum(Pf)
%         sums(6) = sum(Pf.^2)
%         cost    = user-defined computational cost
%
% M        = number of samples for convergence tests
% L        = number of levels for convergence tests
%
% M0       = initial number of samples for MLMC calcs
% Eps      = desired accuracy array for MLMC calcs
% Lmin     = minimum number of levels for MLMC calcs
% Lmax     = maximum number of levels for MLMC calcs
%
% fp       = file handle for printing to file
%

function mlmc_test2(mlmc_l, M, L, M0, model, option, Eps, Lmin, Lmax, fp )

%
% first, convergence tests
%

M = 100*ceil(M/100);   % make M a multiple of 10

PRINTF2(fp,'\n');
PRINTF2(fp,'**********************************************************\n');
PRINTF2(fp,'*** MLMC file version 0.9     produced by              ***\n');
PRINTF2(fp,'*** MATLAB mlmc_test on %s           ***\n',datestr(now));
PRINTF2(fp,'**********************************************************\n');
PRINTF2(fp,'\n');
PRINTF2(fp,'**********************************************************\n');
PRINTF2(fp,'*** Convergence tests, kurtosis, telescoping sum check ***\n');
PRINTF2(fp,'*** using M =%7d samples                           ***\n',M);
PRINTF2(fp,'**********************************************************\n');
PRINTF2(fp,'\n l   ave(Pf-Pc)    ave(Pf)   var(Pf-Pc)  var(Pf)');
PRINTF2(fp,'   kurtosis    check     cost\n-------------------------');
PRINTF2(fp,'------------------------------------------------------\n');

del1 = [];
del2 = [];
var1 = [];
var2 = [];
kur1 = [];
chk1 = [];
cost = [];

for l = 0:L
%  disp(sprintf('l = %d',l))
  sums = 0;
  cst  = 0;
  parfor j=1:100
    RandStream.setGlobalStream( ...
    RandStream.create('mrg32k3a','NumStreams',100,'StreamIndices',j));

    [sums_j, cst_j] = mlmc_l(l,M/100,model,option);
    sums = sums + sums_j/M;
    cst  = cst  + cst_j/M;
  end

  if (l==0)
    kurt = 0.0;
  else
    kurt = (     sums(4)             ...
             - 4*sums(3)*sums(1)     ...
             + 6*sums(2)*sums(1)^2   ...
             - 3*sums(1)*sums(1)^3 ) ...
           / (sums(2)-sums(1)^2)^2;
  end

  cost = [cost cst];
  del1 = [del1 sums(1)];
  del2 = [del2 sums(5)];
  var1 = [var1 sums(2)-sums(1)^2 ];
  var2 = [var2 sums(6)-sums(5)^2 ];
  var1 = max(var1, 1e-10); %fix for cases with var=0
  var2 = max(var2, 1e-10);   
  kur1 = [kur1 kurt ];

  if l==0
    check = 0;
  else
    check = abs(       del1(l+1)  +      del2(l)  -      del2(l+1)) ...
      /    ( 3.0*(sqrt(var1(l+1)) + sqrt(var2(l)) + sqrt(var2(l+1)) )/sqrt(M));
  end
  chk1 = [chk1 check];

  PRINTF2(fp,'%2d  %11.4e %11.4e  %.3e  %.3e  %.2e  %.2e  %.2e \n', ...
          l,del1(l+1),del2(l+1),var1(l+1),var2(l+1),kur1(l+1),chk1(l+1),cst);
end

%
% print out a warning if kurtosis or consistency check looks bad
%

if ( kur1(end) > 100.0 )
  PRINTF2(fp,'\n WARNING: kurtosis on finest level = %f \n',kur1(end));
  PRINTF2(fp,' indicates MLMC correction dominated by a few rare paths; \n');
  PRINTF2(fp,' for information on the connection to variance of sample variances,\n');
  PRINTF2(fp,' see http://mathworld.wolfram.com/SampleVarianceDistribution.html\n\n');
end

if ( max(chk1) > 1.0 )
  PRINTF2(fp,'\n WARNING: maximum consistency error = %f \n',max(chk1));
  PRINTF2(fp,' indicates identity E[Pf-Pc] = E[Pf] - E[Pc] not satisfied; \n');
  PRINTF2(fp,' to be more certain, re-run mlmc_test with larger M \n\n');
end

%
% use linear regression to estimate alpha, beta and gamma
%

L1 = 5;
L2 = L+1;
pa    = polyfit(L1:L2,log2(abs(del1(L1:L2))),1);  alpha = -pa(1);
pb    = polyfit(L1:L2,log2(abs(var1(L1:L2))),1);  beta  = -pb(1);
pg    = polyfit(L1:L2,log2(abs(cost(L1:L2))),1);  gamma =  pg(1);

PRINTF2(fp,'\n******************************************************\n');
PRINTF2(fp,'*** Linear regression estimates of MLMC parameters ***\n');
PRINTF2(fp,'******************************************************\n');
PRINTF2(fp,'\n alpha = %f  (exponent for MLMC weak convergence)\n',alpha);
PRINTF2(fp,' beta  = %f  (exponent for MLMC variance) \n',beta);
PRINTF2(fp,' gamma = %f  (exponent for MLMC cost) \n',gamma);

%
% second, mlmc complexity tests
%

PRINTF2(fp,'\n');
PRINTF2(fp,'***************************** \n');
PRINTF2(fp,'*** MLMC complexity tests *** \n');
PRINTF2(fp,'***************************** \n\n');
PRINTF2(fp,'   eps       value    mlmc_cost   std_cost    N_l \n');
PRINTF2(fp,'----------------------------------------------------------- \n');

% reset random number generators

reset(RandStream.getGlobalStream);
% spmd
%   RandStream.setGlobalStream( ...
%   RandStream.create('mrg32k3a','NumStreams',numlabs,'StreamIndices',labindex));
% end

alpha = max(alpha,0.5);
beta  = max(beta,0.5);

% for i = 1:length(Eps)
%   eps = Eps(i); 
%   
%   [P, Ml, Cl] = mlmc(mlmc_l,M0,model,option,eps,Lmin,Lmax,alpha,beta,gamma);          
%   
%   mlmc_cost = sum(Ml.*Cl);
%   std_cost  = 2*var2(min(end,length(Ml)))*Cl(end) / eps^2;
% 
%   PRINTF2(fp,'%.3e %10.3e  %.3e  %.3e', ...
% 	  eps, P, mlmc_cost, std_cost );
%   PRINTF2(fp,'%9d',Ml);
%   PRINTF2(fp,'\n');
% end

PRINTF2(fp,'\n');

end

%
% function to print to both a file and stdout 
%

function PRINTF2(fp,varargin)
fprintf(fp,varargin{:});
fprintf( 1,varargin{:});
end

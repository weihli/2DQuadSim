% 8/6/13
% findTrajLoad.m
% generate optimal trajectory, assuming only a 1D load
%
% Dependencies: findContConstraints.m, findFixedConstraints.m,
%   findDerivativeCoeff.m, findCostMatrix.m
%
% inputs:
%   r: integer, derivative to minimize in cost function
%   n: integer, order of desired trajectory
%   m: integer, number of pieces in trajectory
%   d: integer, number of dimensions
%   tDes: (m+1) x 1 vector, desired times of arrival at keyframes
%   posDes: r x m x d matrix, desired positions and/or derivatives at keyframes,
%       Inf represents unconstrained values
%       each row i is the value the (i-1)th derivative of column j for
%       dimenison k
%   ineqConst: structure of sx1 arrays, for s constraints, with elements:
%       numConst: integer, number of constraints
%       start: sx1 matrix, keyframes where constraints begin
%       delta: sx1 matrix, maximum distance
%       nc: sx1 matrix, number of intermediate points
%       dim: sxd matrix, the d dimensions that the constraint applies to
%   g: constant integer, gravity
%   l: constant integer, length of cable
% outputs:
%   mNew: final number of pieces in trajectory
%       extra pieces could have been added beacuse of state switches
%   xTL: (n+1) x mNew x d matrix, where row i contains the ith coefficient for
%       the jth trajectory in dimension k
%       xTL is nondimensionalized in time
%       trajectory for load
%   xTQ: (n+1) x mNew x d matrix, where row i contains the ith coefficient for
%       the jth trajectory in dimension k
%       trajectory for quad, only exists when system is in mode 2
%       all coefficients 0 otherwise
%   mode: a x 3 vector, logs mode switches
%       column 1 indicates keyframe switch occurs, column 2 is last mode,
%           column 3 is new mode (redundant, but just to be explicit)
%       1 indicates mode where cable is taut, trajectory is for load
%       2 indicates mode where cable is slack, trajectory is for quadrotor 


function [xTL, xTQ, mode, mNew, tDes] = findTrajLoad1D(r, n, m, d, tDes, posDes, TDes, g, len, mL, mQ)


% check that we are dealing with a 1D problem
if d ~= 1,
    error('not a 1D problem!')
end



% use nondimensionalized time
%t0 = 0;
%t1 = 1;

% we seek trajectories
% x1(t) = cx1,n*t^n + cx1,n-1*t^(n-1) + ... cx1,0;
% ...
% xm(t) = cxm,n*t^n + cxm,n-1*t^(n-1) + ... cxm,0;
% ...
% y1(t) = cy1,n*t^n + cy1,n-1*t^(n-1) + ... cy1,0;
% ...
% z1(t) = cz1,n*t^n + cz1,n-1*t^(n-1) + ... cz1,0;
% ... for d dimensions
% form the state vector x as:
% x = [cx1,(n) cx1,(n-1) ... cx1,1 cx1,0 cx2,n cx2,(n-1) ... cx2,1 cx2,0 .... cxm,0 ....
%       cy1,(n) cy1,(n-1) ... cy1,1 cy1,0 cy2,n cy2,(n-1) ... cy2,1 cy2,0 .... cym,0 ....
%       cz1,(n) cz1,(n-1) ... cz1,1 cz1,0 cz2,n cz2,(n-1) ... cz2,1 cz2,0 .... czm,0]




global options

if (isempty(options))
    options.r = r;
    options.n = n;
    options.m = m;
    options.d = d;
    options.tDes = tDes;
    options.posDes = posDes;
    %options.t0 = t0;
    %options.t1 = t1;
    
    options.gamma = 1e-5;
end




lastStart = 0; %keyframe that trajectory should begin at 
mNew = 0; % final number of segments in trajectory
mode = [];
xTL = [];
xTQ = [];
currentMode = 1; %assume for now system always starts with taut rope



%%%
% check for any keyframes where tension is 0
for i = 0:m,

    
    % if cable is taut
    if currentMode == 1,
      
        
    % if tension at a keyframe is 0, design a trajectory for all the ones
    %   before it leading to this point 
    if TDes(i+1, 1) == 0,
        
        
        % we are now seeking an x, where
        % p = lastSart+1
        % x = [cp,(n) cp,(n-1) ... cp,1 cp,0 ...
        %      c(p+1),n c(p+1),(n-1) ... c(p+1),1 c(p+1),0 .... 
        %      ...
        %      ci,(n) ci,(n-1) ... ci,1 ci,0]^T;

        
        
        % construct Q matrix
        Q_joint = [];
        % lastStart is the keyframe we want to start at
        % lastStart+1 is the trajectory piece we want to start at 
        % i is the keyframe we want to end at 
        % i is also trajectory piece we want to end at
        for j = (lastStart+1):i, 
            t0 = tDes(lastStart+1, 1);
            t1 = tDes(i, 1);
    
            Q = findCostMatrix(n, r, t0, t1);
            
            Q_joint = blkdiag(Q_joint, Q);
        end

        
        
        % construct A matrix
        
        % make a new desired position matrix based on the keyframes being
        %   optimized
        posDesNew = zeros(r, i-lastStart);
        tDesN = zeros(i-lastStart, 1);
        for j = 0:i-lastStart,
            posDesNew(:, j+1) = posDes(:, lastStart+j+1);
            tDesN(j+1, 1) = tDes(lastStart+j+1 ,1);
        end
        

        
        % construct fixed value constraints and continuity constraints 
        [A_fixed, b_fixed] = findFixedConstraints(r, n, i-lastStart, 1, posDesNew, t0, t1, tDesN, 0);
        %[A_cont, b_cont] = findContConstraints(r, n, i-lastStart, 1, posDesNew, t0, t1);
        
        % put in one matrix - recall there is only one dimension here
        %A_eq = [A_fixed; A_cont];
        %b_eq = [b_fixed; b_cont];
        A_eq = A_fixed;
        b_eq = b_fixed;
        
        
        
        % constraint the velocity to be greater than 0 (implying no
        %   overshooting)
        A_ineq = zeros(1, n+1);
        derCoeff = findDerivativeCoeff(n, 1);
        A_ineq(1, :) = -derCoeff(2, :); %pick out velocity vector
            % note we skip evaluating at time t1 beacuse time is
            % nondimensionalized and t1 =1 
        b_ineq = 0;
        
        % find this trajectory
        xT_all = quadprog(Q_joint,[],A_ineq,b_ineq,A_eq,b_eq);
        
        
        %%%
        % explicitly break tracjetory into its piecewise parts for output
        xT_this = zeros((n+1), i-lastStart);
        for j = 1:i-lastStart,
            xT_this(:, j) = xT_all((j-1)*(n+1)+1:j*(n+1));
        end
        xTL = [xTL xT_this];
        
        % add empty trajectories to quad
        [a, b] = size(xT_this);
        xTQ = [xTQ [xTL(1:n, 1);xTL(n+1, 1)+1]];
        
        mNew = mNew+(i-lastStart); %add new trajectory segments added
        mode = [mode; [i 1 2]];

    
        
        lastStart = i;

        currentMode = 2;

 
    end
        
    elseif currentMode == 2,
        

        
        %%% construct conditions for finding quadrotor trajectory
        
        % assume for now we have a full set of constraints at the end of
        %   the free fall
        posDesQ = zeros(4, 2); % we want to optimize snap of quadrotor between 2 points
        
        % find states at moment of T = 0
        [temp, ~] = evaluateTraj(tDes(2, 1), n, 1, 1, xTL(:, mNew), tDes, 4, [])

        
        % beginning quadrotor position, velocity can be derived from state at
        %   keyframe i
        posDesQ(1, 1) = temp(1, 1)+len; %xQ = xL+l
        posDesQ(2:4, 1) = temp(2:4, 1); % all higher derivatives equal
        
        % find displacement
        d = posDes(1, 3) - temp(1, 1)
        % find time it takes to reach beginning of free fall to end
        % take the larger time - assume this is positive
        t_temp = roots([-g*1/2 temp(2, 1) -d]); % solve for -1/2gt^2+vit - d = 0
        if (t_temp(1, 1) > t_temp(2, 1)),
            t = t_temp(1, 1);
        else
            t = t_temp(2, 1);
        end
        t
        %t = t+tDes(2, 1)
        
        
        
        
        vLminus = temp(2, 1) - g*t; % solve for vf = v1-gt
        vLplus = posDes(2, i+1);
        
        % solve for vQ final 
        vQminus = ((mL+mQ)*vLplus+mL*vLminus)/mQ;
        posDesQ(2, 2) = vQminus;
        
        posDesQ(1, 2) = posDes(1, i+1)+len; % again, xQ = xL+l
        posDesQ(3:4, 2) = Inf;
        
        
        
        
        %%% find trajectory
        % construct QP problem - note that there is always only 1 segment
        % construct Q matrix
        Q = findCostMatrix(7, 4, tDes(2, 1), tDes(3, 1));
        
        posDesQ
        % find A matrix
        [A_fixed, b_fixed] = findFixedConstraints(4, 7, 1, 1, posDesQ, t0, t1, tDes(2:3, 1), 0);
        A_fixed 
        b_fixed
        % find trajectory
        xT_all = quadprog(Q,[],[],[],A_fixed, b_fixed);
        
        
        
        
        %%%
        % add trajectory
        
        % add to quad trajectory
        xTQ = [xTQ [zeros(n+1-8, 1); xT_all]];
        
        % add free fall equations of motion for the load
        % x = -1/2*g*t^2 + vi*t + xi
        % v = -a*t + vi
        % a = -g;
        % all higher derivatives = 0;
        
        % first n-2 terms are 0
        xTL = [xTL [zeros(n-2, 1); -1/2*g; temp(2, 1)+g*tDes(2, 1); temp(1, 1)-temp(2, 1)*tDes(2, 1)-0.5*g*tDes(2, 1)^2]];
        
        
        
        % add a time for this new time segment
        %tDesNew = [tDes(1:i, 1); tDes(i, 1)+t; tDes(i+1:m+1, 1)]
        
        
        
        mNew = mNew+1; %add new trajectory segments added
        mode = [mode; [i 2 1]];
        
        
        
        

        
        
        
        currentMode = 1;
        lastStart = i;
         
        
        

    end
end








% %%%
% % construct equality constraints
% A_opt = [];
% b_opt = [];
% 
% for dim = 1:d,
%     
%     % construct fixed value constraints
%     [A_fixed, b_fixed] = findFixedConstraints(r, n, m, dim, posDes, t0, t1, [], 1);
%     [A_cont, b_cont] = findContConstraints(r, n, m, dim, posDes, t0, t1);
%     
%     % put each A_eq for each dimension into block diagonal matrix
%     A_opt = blkdiag(A_opt, [A_fixed; A_cont]);
%     b_opt = [b_opt; [b_fixed; b_cont]];
%     
% end
% 
% 
% 
% 
% 
% %%%
% % construct any inequality constraints
% [A_ineq, b_ineq] = constructCorrConstraints(n, m, d, posDes, ineqConst, t0, t1);
% 
% 
% 
% 
% %%%
% % find optimal trajectory through quadratic programming
% %xT_all = quadprog(Q_opt,[],A_ineq, b_ineq,A_opt,b_opt);
% xT_all = fmincon(@costfunction,zeros((n+1)*m*d, 1),A_ineq, b_ineq, A_opt,b_opt, [], [], 'tensionConst');
% 
% 
% 
% %%%
% % explicitly break trajectory into its piecewise parts and dimensions for output
% xT = zeros((n+1), m, d);
% for dim = 1:d,
%     thisxT = xT_all((dim-1)*(n+1)*m+1:dim*(n+1)*m);
%     for j = 1:m,
%         xT(:, j, dim) = thisxT((j-1)*(n+1)+1:j*(n+1));
%     end
% end



end







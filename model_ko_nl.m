% Copyright (C) 2018 - Mykhayl Puzanov
%
% Date of creation: 24.04.2018
%
% The test of varivolt movements and control

T = 0.1 % sampling time

% X = [x1; x2] where x1 - is position, x2 - is velocity
% x1 has range 200 .. 1000mm 
% we cannot measure the position directly, but we have an indirect measurement by voltage
% U = kv * x1
% U has range [30V .. 95V]

% measurement 
Pmin = 0 % [mm] minimal position
Pmax = 1000 % [mm] maximal position
Umin = 30 % [V] minimal voltage
Umax = 95 % [V] maximal voltage

% a changing of position is doing by a motor which can be represented as First-Order-Unit
% y(n+1) = a*y(n) + b*u(n+1)
% a = Tp / (Tp + T)
% b = Ku * T / (Tp + T)

nm = 1350 % [1/min] nominal speed

Tp = 2
Qmin = 0
Qmax = 100
Qlimp = Qmax
Qlimn = -Qmax
Ku = (nm - 0) / (Qmax -Qmin)
a2 = Tp / (Tp + T)
b2 = Ku * T / (Tp + T)

% a transformer translation factor depends from a lineer position of secondary coil
% the linear position {p} is an intergral from the motor speed {w}
% p(n+1) = p(n) + kw * w(n + 1)


Tmr = 120 % [s] a movement time from end to end

vx = (Pmax - Pmin) / Tmr % nominal linear speed
kw = vx / nm % speed translation factor
a1 = kw * T
b1 = 0

% A state-space matrix

A = [1, a1; 0, a2]
% For a control we use the "voltage" which is changing a motor speed
B = [0; b2]

% measurement matrix
kv = (Umax - Umin)/(Pmax - Pmin)
U0 = Umax - kv*Pmax
% U = kv*P + U0
C = [kv, 0]

% feedworward
%D = [0; 0]
D = 0

% check a controlability
% n = 2, R = [B, A*B]
R = [B, A*B]
disp(rank(R))

% check observability
% n = 2 
O = [C; C*A]
disp(rank(O))

% closed-loop model
% complex poles
pr = -0.87; % is good
pi = 0.1;
p = [complex(-pr, +pi), complex(-pr, -pi)]
Ns = 14.898461 % scaling factor, acceptable only for these poles

K = place(A,B, p)

Ac = A - B*K

eig(A)
eig(Ac)

Bc = B * Ns

Sc = ss(Ac, Bc, C, D, T);

% Controller with an observer
% an observer character
op = [0.98; 0.67]
L = place(A', C', op)'

Nc = 6.9374759
Ao = A - L*C

% simulation

% set of testing reference signals
Tmax = 1800;
t=0:T:Tmax;
n = length(t);
ui = zeros(1, n); ui(1) = 1;
us = ones(1, n); us(1) = 0;
uf = abs(sin(0.02*t))
ug = us + 0.1 * sin(0.005*t)
uh = us + 0.001 * t

% assign signal
r = ug * (Umax - Umin) * 0.5


% initial state
x0 = [Pmin;0]

%%%%%%%%%%%%%%%%%%%%%

% closed-loop system (ideal)
x2 = zeros(2, n); x2(:,1) = x0
y2 = zeros(1, n)
u2 = r
for i=1:n-1 
    ux = Ns * r(i) - K *x2(:, i); % error signal
    % include a limiter of manipulation signal
    if ux > Qlimp 
      ux = Qlimp; 
    end
    if ux < Qlimn
      ux = Qlimn;
    end
    u2(i) = ux;
    % plant simulation
    y2(:, i) = C * x2(:, i);
    x2(:, i + 1) = A * x2(:, i) + B * u2(i);
endfor
y2(:, n) = C * x2(:, n);

% closed-loop system with the observer (Kalman filter)

% Kalman filter weighting matrixes 
Usd = 16
%Q = [0.1, 0; 0, 0.01] % is very good
Q = [0.1, 0.01; 0.01, 0.1]
S = (Usd*1)^2
Nf = 14.702287


x3 = zeros(2, n);
% initial state for model  
x3(:,1) = x0; 
y3 = zeros(1, n);

x3hat = zeros(2, n);
% initial state for Kalman filter 
% x3hat(:,1) = x0;
y3hat = y3;
P = zeros (size (A));

% reference and manipulation signales
u3 = r;

% ns3 = grand(1, n, "nor", 0, Usd)
ns3 = Usd.*randn(1,n);
y3n = y3;
ye = y3;
err = y3;

% prepare a Kalman filter gain matrix 
II = eye(size(P));
for j=1:600
    Pminus = A * P * A' + Q;
    Kp = (C * Pminus * C' + S)^-1;
    Kk = Pminus * C' * Kp;
    P = (II - Kk*C) * Pminus;
endfor

% controller aux. state vars
crz = 0; % manipulation cross zero mark
dcd = 0; % delay afte direction changing
dss = 0; % delay after stop
Kg = 15 % gain
Tp = 5 % pause between the direction changes (cross zero after delay)
Ts = 20 % stop pause
ux = [0,0];

for i=1:n-1  
    % plant simulation
    y3(:, i) = C * x3(:, i);    
    x3(:, i + 1) = A * x3(:, i) + B * u3(i);
    % simulate a noised measurement
    y3n(:,i) = y3(:,i) + ns3(:,i)
    
    % controller simulation
    y3hat(:, i) = C * x3hat(:, i);
    % Kalman filter
    x3hatminus = A * x3hat(:, i) + B * u3(:, i);

    % estimation error
    ey = y3n(:,i) - C * x3hatminus;
    ye(:,i) = ey;
    % X expectation
    x3hat(:, i + 1) = x3hatminus + Kk * ey;

    % calculate manipulation 
    err(i) = r(i) - y3hat(:, i);
    if abs(err(i)) < 0.5
        ex = 0;
    else
        ex = err(i);
    end
     
    ux(3) = Kg * ex;
    crz = ((ux(3) > 0) && (ux(2) < 0)) || ((ux(3) < 0) && (ux(2) > 0)) ;
    ux(2) = ux(3);
    
    if crz 
       dcd = i; 
    end
    if dcd + Tp <=i
      dcd = 0; 
    end
    
    if abs(ux(2)) < 0.1 
       dss = i; 
    end
    if dss + Ts <=i 
       dss = 0; 
    end
    
    if (dcd > 0) || (dss > 0) 
      ux(1) = 0;
    else 
      ux(1) = ux(2);
    end
        
    % include a limiter of manipulation signal
    if ux(1) > Qlimp 
      ux(1) = Qlimp;
    end
    if ux(1) < Qlimn
      ux(1) = Qlimn; 
    end
    u3(i+1) = ux(1);
endfor

y3(:, n) = C * x3(:, n);
y3hat(:, n) = C * x3hat(:, n);

xe3 = x3 - x3hat;
ye3 = y3 - y3hat;

% plotting

f1 = figure();
subplot(211)'
plot([t', t'], [r', y2']);
subplot(212);
plot([t', t'], [r', y3']);


f2 = figure();
subplot(211);
plot(x2');
subplot(212);
plot(x3');

f3 = figure();
subplot(211);
plot(u2);
subplot(212);
plot(u3);

f4 = figure();
subplot(211);
plot(xe3');
subplot(212);
plot(ye3');
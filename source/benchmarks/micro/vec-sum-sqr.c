typedef struct Vec3_t { double x, y, z; } Vec3;

double sumSqr(Vec3 v) {

    double sum = 0;

    for (int i = 0; i < 1000000000; ++i)
    {
        double xx = v.x * v.x;
        double yy = v.y * v.y;
        double zz = v.z * v.z;
        sum += xx + yy + zz;
    }

    return sum;
}

Vec3 v = {x:1, y: -1, z:0.5};

void main()
{
    double sum = sumSqr(v);

    printf("%lf", sum);
}


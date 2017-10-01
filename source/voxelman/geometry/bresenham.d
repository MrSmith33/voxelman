/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.bresenham;

int abs(const int num) @nogc nothrow pure { return num < 0 ? -num : num; }

void bresenham(int x1, int y1, const int x2, const int y2, scope void delegate(int x, int y) plot)
{
    int delta_x = x2 - x1;
    immutable int ix = (delta_x > 0) - (delta_x < 0);
    delta_x = abs(delta_x) << 1;

    int delta_y = y2 - y1;
    immutable int iy = (delta_y > 0) - (delta_y < 0);
    delta_y = abs(delta_y) << 1;

    plot(x1, y1);

    if (delta_x >= delta_y)
    {
        int error = delta_y - (delta_x >> 1);

        while (x1 != x2)
        {
            if ((error > 0) || (!error && (ix > 0)))
            {
                error -= delta_x;
                y1 += iy;
            }

            error += delta_y;
            x1 += ix;

            plot(x1, y1);
        }
    }
    else
    {
        int error = delta_x - (delta_y >> 1);

        while (y1 != y2)
        {
            if ((error > 0) || (!error && (iy > 0)))
            {
                error -= delta_y;
                x1 += ix;
            }

            error += delta_x;
            y1 += iy;

            plot(x1, y1);
        }
    }
}
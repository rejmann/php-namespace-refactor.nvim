<?php

namespace App\Foo;

class Consumer
{
    public function __construct(private Bar $bar)
    {
    }
}

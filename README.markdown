# progress

http://github.com/toy/in_threads

## DESCRIPTION:

Easily execute ruby code in parallel

## SYNOPSIS:

By default there is maximum of 10 simultaneous threads

    urls.in_threads.each do |url|
      url.save_to_disk
    end

    urls.in_threads.map do |url|
      url.fetch
    end

    numbers.in_threads(2).map do |number|
      …
      # whery long and complicated formula
      # using only 2 threads
    end

You can use any Enumerable method but it is up to you if this is good

    urls.in_threads.any?(&:ok?)
    urls.in_threads.all?(&:ok?)

## REQUIREMENTS:

ruby )))

## INSTALL:

    sudo gem install in_threads

## Copyright

Copyright (c) 2010 Ivan Kuchin. See LICENSE.txt for details.

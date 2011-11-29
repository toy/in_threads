# in_threads

Easily execute ruby code in parallel.

## Installation

    gem install progress

## Usage

By default there is maximum of 10 simultaneous threads

    urls.in_threads.map do |url|
      url.fetch
    end

    urls.in_threads.each do |url|
      url.save_to_disk
    end

    numbers.in_threads(2).map do |number|
      …
      # whery long and complicated formula
      # using only 2 threads
    end

You can use any Enumerable method but it is up to you if this is good

    urls.in_threads.any?(&:ok?)
    urls.in_threads.all?(&:ok?)

## Copyright

Copyright (c) 2010-2011 Ivan Kuchin. See LICENSE.txt for details.
